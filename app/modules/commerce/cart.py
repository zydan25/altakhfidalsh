from ...extensions import db
from ...models import Cart, CartItem, Product, ProductVariant
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
            response.append({
                "id": item.id,
                "variant_id": item.variant_id,
                "qty": item.qty,
                "unit_price": str(price.final),
                "currency_id": context.currency_id,
                "currency_code": context.currency_code,
                "line_total": str(price.final * item.qty),
            })
            subtotal += price.final * item.qty
        db.session.commit()
        return {"id": cart.id, "items": response, "subtotal": str(subtotal)}


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
