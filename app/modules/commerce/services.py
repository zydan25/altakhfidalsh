from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import and_, or_

from ...extensions import db
from ...models import (
    Cart,
    CartItem,
    City,
    Customer,
    CustomerAddress,
    InventoryLocation,
    Order,
    OrderItem,
    OrderStatusHistory,
    Product,
    ProductVariant,
    ShippingMethod,
    ShippingRate,
    StockInventory,
)
from ...services.pricing import price_for_customer


ORDER_STATUSES = (
    "created",
    "awaiting_payment",
    "paid",
    "processing",
    "shipped",
    "delivered",
    "returned",
    "cancelled",
)


class CommerceService:
    @staticmethod
    def _address_snapshot(address):
        return {
            "id": address.id,
            "recipient_name": address.recipient_name,
            "phone": address.phone,
            "country_id": address.country_id,
            "city_id": address.city_id,
            "district": address.district,
            "street": address.street,
            "landmark": address.landmark,
            "lat": str(address.lat) if address.lat is not None else None,
            "lng": str(address.lng) if address.lng is not None else None,
        }

    @staticmethod
    def _resolve_shipping(city_id, subtotal):
        city = db.session.get(City, city_id) if city_id else None
        rows = (
            ShippingRate.query
            .join(ShippingMethod, ShippingMethod.id == ShippingRate.method_id)
            .filter(
                ShippingRate.is_active.is_(True),
                ShippingMethod.is_active.is_(True),
                or_(ShippingRate.city_id == city_id, ShippingRate.city_id.is_(None)),
                or_(ShippingRate.region_id == (city.region_id if city else None), ShippingRate.region_id.is_(None)),
            )
            .order_by(
                ShippingRate.city_id.is_(None),
                ShippingRate.region_id.is_(None),
                ShippingRate.price.asc(),
            )
            .all()
        )
        for row in rows:
            if row.min_order is not None and subtotal < row.min_order:
                continue
            if row.max_order is not None and subtotal > row.max_order:
                continue
            if row.free_over is not None and subtotal >= row.free_over:
                return Decimal("0")
            return Decimal(row.price)
        return Decimal("0")

    @staticmethod
    def create_order(payload):
        customer_id = int(payload["customer_id"])
        address_id = int(payload["address_id"])
        requested_currency_id = payload.get("currency_id")
        items = payload.get("items") or []
        if not items:
            raise ValueError("order must contain at least one item")

        customer = db.session.get(Customer, customer_id)
        address = db.session.get(CustomerAddress, address_id)
        if customer is None:
            raise LookupError("customer not found")
        if address is None or address.customer_id != customer_id:
            raise ValueError("shipping address is invalid")
        if address.city_id is None:
            raise ValueError("shipping address must have a city")

        with db.session.begin_nested():
            context, _ = price_for_customer(
                base_price_sar=Decimal("0"),
                customer_id=customer_id,
                city_id=address.city_id,
                currency_id=int(requested_currency_id) if requested_currency_id else None,
            )
            order_items = []
            subtotal = Decimal("0")

            for raw in items:
                variant_id = int(raw["variant_id"])
                qty = int(raw.get("qty", 1))
                if qty <= 0:
                    raise ValueError("quantity must be positive")

                variant = db.session.get(ProductVariant, variant_id)
                if variant is None or variant.product_id is None or not variant.is_active:
                    raise ValueError(f"variant {variant_id} is unavailable")
                product = db.session.get(Product, variant.product_id)
                if product is None or product.status != "published" or not product.is_active:
                    raise ValueError(f"product for variant {variant_id} is unavailable")

                context, price = price_for_customer(
                    base_price_sar=Decimal(product.base_price),
                    customer_id=customer_id,
                    city_id=address.city_id,
                    currency_id=context.currency_id,
                )
                line_total = price.final * qty
                subtotal += line_total

                stock_rows = (
                    StockInventory.query
                    .join(InventoryLocation, InventoryLocation.id == StockInventory.location_id)
                    .filter(
                        StockInventory.variant_id == variant_id,
                        StockInventory.available >= qty,
                        StockInventory.on_hand >= StockInventory.reserved + qty,
                        InventoryLocation.is_active.is_(True),
                    )
                    .with_for_update()
                    .order_by(InventoryLocation.city_id.isnot(address.city_id), StockInventory.available.desc())
                    .all()
                )
                if not stock_rows:
                    raise ValueError(f"insufficient stock for variant {variant_id}")
                stock = stock_rows[0]
                stock.reserved += qty
                stock.available = stock.on_hand - stock.reserved

                order_items.append(
                    {
                        "variant": variant,
                        "product": product,
                        "price": price,
                        "context": context,
                        "qty": qty,
                    }
                )

            shipping = CommerceService._resolve_shipping(address.city_id, subtotal)
            total = subtotal + shipping

            order = Order(
                order_no=f"ALT-{datetime.now(timezone.utc):%Y%m%d%H%M%S}-{customer_id}-{uuid4().hex[:6].upper()}",
                customer_id=customer_id,
                address_snapshot=CommerceService._address_snapshot(address),
                city_id=address.city_id,
                currency_id=context.currency_id,
                pricing_group_id=context.pricing_group_id,
                fx_rate=order_items[0]["price"].fx_rate,
                markup_percent=(
                    order_items[0]["context"].override_percent
                    if order_items[0]["context"].override_percent is not None
                    else order_items[0]["context"].rule.percent_markup
                ),
                markup_fixed=(
                    order_items[0]["context"].override_fixed
                    if order_items[0]["context"].override_fixed is not None
                    else order_items[0]["context"].rule.fixed_markup
                ),
                subtotal=subtotal,
                discount=Decimal("0"),
                shipping=shipping,
                total=total,
                status="created",
                payment_status="unpaid",
                shipping_status="pending",
            )
            db.session.add(order)
            db.session.flush()

            for item in order_items:
                product = item["product"]
                price = item["price"]
                context = item["context"]
                db.session.add(
                    OrderItem(
                        order_id=order.id,
                        product_id=product.id,
                        variant_id=item["variant"].id,
                        sku_snapshot=item["variant"].sku,
                        name_snapshot=product.name,
                        base_price_sar=price.base_sar,
                        fx_rate=price.fx_rate,
                        markup_percent=(
                            context.override_percent
                            if context.override_percent is not None
                            else context.rule.percent_markup
                        ),
                        markup_fixed=(
                            context.override_fixed
                            if context.override_fixed is not None
                            else context.rule.fixed_markup
                        ),
                        sale_price_display=price.final,
                        qty=item["qty"],
                        total=price.final * item["qty"],
                    )
                )

            db.session.add(
                OrderStatusHistory(
                    order_id=order.id,
                    from_status=None,
                    to_status="created",
                    actor_type="customer",
                    actor_id=customer_id,
                    note="Order created",
                )
            )

        db.session.commit()
        return CommerceService.serialize_order(order)

    @staticmethod
    def serialize_order(order):
        return {
            "id": order.id,
            "order_no": order.order_no,
            "customer_id": order.customer_id,
            "city_id": order.city_id,
            "currency_id": order.currency_id,
            "pricing_group_id": order.pricing_group_id,
            "fx_rate": str(order.fx_rate),
            "subtotal": str(order.subtotal),
            "discount": str(order.discount),
            "shipping": str(order.shipping),
            "total": str(order.total),
            "status": order.status,
            "payment_status": order.payment_status,
            "shipping_status": order.shipping_status,
            "address_snapshot": order.address_snapshot,
        }

    @staticmethod
    def transition_order(order_id, to_status, actor_type="admin", actor_id=None, note=None):
        order = db.session.get(Order, order_id)
        if order is None:
            raise LookupError("order not found")
        if to_status not in ORDER_STATUSES:
            raise ValueError("invalid order status")
        if order.status == to_status:
            return CommerceService.serialize_order(order)

        current_index = ORDER_STATUSES.index(order.status) if order.status in ORDER_STATUSES else 0
        target_index = ORDER_STATUSES.index(to_status)
        allowed_backwards = {("cancelled", "created"), ("returned", "processing")}
        if target_index < current_index and (order.status, to_status) not in allowed_backwards:
            raise ValueError("illegal status transition")

        previous = order.status
        order.status = to_status
        db.session.add(
            OrderStatusHistory(
                order_id=order.id,
                from_status=previous,
                to_status=to_status,
                actor_type=actor_type,
                actor_id=actor_id,
                note=note,
            )
        )
        db.session.commit()
        return CommerceService.serialize_order(order)

    @staticmethod
    def add_to_cart(customer_id, variant_id, qty=1):
        customer = db.session.get(Customer, customer_id)
        variant = db.session.get(ProductVariant, variant_id)
        if customer is None or variant is None or not variant.is_active:
            raise LookupError("customer or variant not found")
        if qty <= 0:
            raise ValueError("quantity must be positive")
        cart = Cart.query.filter_by(customer_id=customer_id).first()
        if cart is None:
            cart = Cart(customer_id=customer_id)
            db.session.add(cart)
            db.session.flush()
        item = CartItem.query.filter_by(cart_id=cart.id, variant_id=variant_id).first()
        if item:
            item.qty += qty
        else:
            item = CartItem(cart_id=cart.id, variant_id=variant_id, qty=qty, selected_options={})
            db.session.add(item)
        db.session.commit()
        return {"cart_id": cart.id, "variant_id": variant_id, "qty": item.qty}
