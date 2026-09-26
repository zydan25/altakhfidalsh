from ...extensions import db
from ...models import Cart, CartItem, Product, ProductMedia, ProductVariant, MediaAsset, Color, Size
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
        db.session.commit()
        return {"id": cart.id, "items": response, "subtotal": str(subtotal)}


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
        item.qty = qty
        db.session.commit()
        return {"ok": True, "item_id": item.id, "qty": item.qty}


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
