from ...extensions import db
from ...models import (
    Cart, CartItem, Product, ProductMedia, ProductVariant,
    MediaAsset, Color, Size, Currency, InventoryLocation, StockInventory,
)
from ...services.pricing import price_for_customer


class CartService:
    @staticmethod
    def get_cart(customer_id, currency_id=None):
        cart = Cart.query.filter_by(customer_id=customer_id).first()
        if cart is None:
            return {"id": None, "items": [], "subtotal": "0"}
        items = CartItem.query.filter_by(cart_id=cart.id).order_by(CartItem.id).all()
        response = []
        subtotal = 0
        subtotal_sar = 0
        for item in items:
            variant = db.session.get(ProductVariant, item.variant_id)
            product = db.session.get(Product, variant.product_id) if variant else None
            if variant is None or product is None:
                continue
            context, price = price_for_customer(
                base_price_sar=product.base_price,
                customer_id=customer_id,
                currency_id=currency_id or cart.currency_id,
            )
            item.unit_price_snapshot = price.final
            currency = db.session.get(Currency, context.currency_id)
            media = (
                db.session.query(MediaAsset)
                .join(ProductMedia, ProductMedia.asset_id == MediaAsset.id)
                .filter(ProductMedia.product_id == product.id)
                .order_by(ProductMedia.sort_order, ProductMedia.id)
                .first()
            )
            color = db.session.get(Color, variant.color_id) if variant.color_id else None
            size = db.session.get(Size, variant.size_id) if variant.size_id else None
            response.append({
                "id": item.id,
                "variant_id": item.variant_id,
                "qty": item.qty,
                "unit_price": str(price.final),
                "currency_id": context.currency_id,
                "currency_code": context.currency_code,
                "currency_symbol": (currency.symbol or currency.code) if currency else context.currency_code,
                "line_total": str(price.final * item.qty),
                "product_id": product.id,
                "product_name": product.name,
                "sku": variant.sku,
                "image_url": media.url if media else None,
                "color_name": color.name if color else None,
                "size_label": size.label if size else None,
                "variant_display": " / ".join(
                    x for x in (
                        color.name if color else None,
                        size.label if size else None,
                    ) if x
                ),
            })
            subtotal += price.final * item.qty
            subtotal_sar += price.base_sar * item.qty
            response[-1]["selected_options"] = dict(item.selected_options or {})
        db.session.commit()
        return {
            "id": cart.id,
            "items": response,
            "subtotal": str(subtotal),
            "subtotal_sar": str(subtotal_sar),
            "currency_id": response[0]["currency_id"] if response else (cart.currency_id or None),
            "currency_code": response[0]["currency_code"] if response else None,
            "currency_symbol": response[0]["currency_symbol"] if response else None,
        }


    @staticmethod
    def set_item_qty(customer_id, item_id, qty):
        cart = Cart.query.filter_by(customer_id=customer_id).first()
        if cart is None:
            raise LookupError("cart not found")
        item = CartItem.query.filter_by(cart_id=cart.id, id=item_id).first()
        if item is None:
            raise LookupError("cart item not found")
        qty = int(qty)
        if qty < 1:
            db.session.delete(item)
            db.session.commit()
            return {"ok": True, "deleted": True}

        stock_rows = (
            StockInventory.query
            .join(InventoryLocation, InventoryLocation.id == StockInventory.location_id)
            .filter(
                StockInventory.variant_id == item.variant_id,
                InventoryLocation.is_active.is_(True),
            )
            .with_for_update()
            .all()
        )
        available_qty = sum(max(0, int(row.available or 0)) for row in stock_rows)
        if qty > available_qty:
            raise ValueError(f"المتاح لهذا الاختيار {available_qty} فقط.")
        item.qty = qty
        db.session.commit()
        return {
            "ok": True,
            "item_id": item.id,
            "qty": item.qty,
            "available_qty": available_qty,
        }


    @staticmethod
    def remove_item(customer_id, item_id):
        cart = Cart.query.filter_by(customer_id=customer_id).first()
        if cart is None:
            raise LookupError("cart not found")
        item = CartItem.query.filter_by(cart_id=cart.id, id=item_id).first()
        if item is None:
            raise LookupError("cart item not found")
        db.session.delete(item)
        db.session.commit()
        return {"ok": True}


    @staticmethod
    def clear_cart(customer_id):
        cart = Cart.query.filter_by(customer_id=customer_id).first()
        if cart is None:
            return {"ok": True}
        CartItem.query.filter_by(cart_id=cart.id).delete()
        db.session.commit()
        return {"ok": True}
