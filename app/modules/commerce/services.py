from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import and_, or_

from ...extensions import db
from ...models import (
    Cart,
    CartItem,
    City,
    Conversation,
    Customer,
    CustomerAddress,
    ExchangeRate,
    InventoryLocation,
    MediaAsset,
    Message,
    MessageAttachment,
    Order,
    OrderItem,
    OrderItemOption,
    OrderStatusHistory,
    PaymentMethod,
    PaymentProof,
    PaymentTransaction,
    Color,
    Product,
    ProductMedia,
    ProductVariant,
    Refund,
    ReturnItem,
    ReturnRequest,
    Shipment,
    ShipmentEvent,
    Size,
    ShippingMethod,
    ShippingRate,
    StockInventory,
    WarrantyClaim,
)
from ...services.pricing import price_for_customer
from ...services.shipping import ShippingService


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
            "city_area_id": address.city_area_id,
            "district": address.district,
            "street": address.street,
            "landmark": address.landmark,
            "lat": str(address.lat) if address.lat is not None else None,
            "lng": str(address.lng) if address.lng is not None else None,
        }

    @staticmethod
    def _resolve_shipping(customer_id, city_id, area_id, subtotal_sar, fx_rate):
        quote = ShippingService.quote(
            customer_id=customer_id,
            city_id=city_id,
            area_id=area_id,
            subtotal_sar=Decimal(subtotal_sar),
            fx_rate=Decimal(fx_rate),
        )
        return quote

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
            subtotal_sar = Decimal("0")

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
                subtotal_sar += price.base_sar * qty

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
                        "selected_options": raw.get("selected_options") or raw.get("options") or {},
                    }
                )

            shipping_quote = CommerceService._resolve_shipping(
                customer_id,
                address.city_id,
                address.city_area_id,
                subtotal_sar,
                order_items[0]["price"].fx_rate,
            )
            shipping = shipping_quote.price_display
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
                shipping_base_sar=shipping_quote.price_sar,
                shipping_rate_id=shipping_quote.rate_id,
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
                order_item = OrderItem(
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
                db.session.add(order_item)
                db.session.flush()

                selected_options = item.get("selected_options") or {}
                if isinstance(selected_options, dict):
                    selected_options = [{"name": key, "value": value} for key, value in selected_options.items()]
                for option in selected_options:
                    if isinstance(option, dict):
                        option_name = str(option.get("name") or option.get("option_name") or "").strip()
                        option_value = str(option.get("value") or option.get("option_value") or "").strip()
                    else:
                        option_name, option_value = "اختيار", str(option).strip()
                    if option_name and option_value:
                        db.session.add(OrderItemOption(
                            order_item_id=order_item.id,
                            option_name=option_name,
                            option_value=option_value,
                        ))

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
    def serialize_order_detail(order):
        data = CommerceService.serialize_order(order)

        customer = db.session.get(Customer, order.customer_id)
        data["customer"] = {
            "id": customer.id if customer else order.customer_id,
            "name": customer.name if customer else None,
            "phone": customer.phone_normalized if customer else None,
            "email": customer.email if customer else None,
        }

        order_items = OrderItem.query.filter_by(order_id=order.id).order_by(OrderItem.id).all()
        data["items"] = []
        for item in order_items:
            variant = db.session.get(ProductVariant, item.variant_id) if item.variant_id else None
            color = db.session.get(Color, variant.color_id) if variant and variant.color_id else None
            size = db.session.get(Size, variant.size_id) if variant and variant.size_id else None
            media_rows = ProductMedia.query.filter_by(product_id=item.product_id).order_by(ProductMedia.sort_order, ProductMedia.id).all()
            data["items"].append({
                "id": item.id,
                "product_id": item.product_id,
                "variant_id": item.variant_id,
                "sku": item.sku_snapshot,
                "name": item.name_snapshot,
                "base_price_sar": str(item.base_price_sar),
                "fx_rate": str(item.fx_rate),
                "markup_percent": str(item.markup_percent),
                "markup_fixed": str(item.markup_fixed),
                "sale_price_display": str(item.sale_price_display),
                "qty": item.qty,
                "total": str(item.total),
                "variant_display": {
                    "color": {"id": color.id, "name": color.name, "hex_code": color.hex_code} if color else None,
                    "size": {"id": size.id, "group": size.group, "code": size.code, "label": size.label} if size else None,
                },
                "media": [
                    {
                        "id": row.id,
                        "asset_id": row.asset_id,
                        "url": (
                            db.session.get(MediaAsset, row.asset_id).url
                            if db.session.get(MediaAsset, row.asset_id)
                            else None
                        ),
                        "role": row.role,
                        "sort_order": row.sort_order,
                    }
                    for row in media_rows
                ],
                "options": [
                    {"name": option.option_name, "value": option.option_value}
                    for option in OrderItemOption.query.filter_by(order_item_id=item.id).order_by(OrderItemOption.id).all()
                ],
            })

        data["status_history"] = [
            {
                "id": row.id,
                "from_status": row.from_status,
                "to_status": row.to_status,
                "actor_type": row.actor_type,
                "actor_id": row.actor_id,
                "note": row.note,
                "created_at": row.created_at.isoformat() if row.created_at else None,
            }
            for row in OrderStatusHistory.query.filter_by(order_id=order.id).order_by(OrderStatusHistory.created_at, OrderStatusHistory.id).all()
        ]

        payments = (
            PaymentTransaction.query
            .filter_by(order_id=order.id)
            .order_by(PaymentTransaction.id)
            .all()
        )
        data["payments"] = []
        for row in payments:
            method = db.session.get(PaymentMethod, row.method_id)
            data["payments"].append({
                "id": row.id,
                "method_id": row.method_id,
                "method_name": method.name if method else None,
                "amount": str(row.amount),
                "currency_id": row.currency_id,
                "provider_ref": row.provider_ref,
                "status": row.status,
                "paid_at": row.paid_at.isoformat() if row.paid_at else None,
            })

        proofs = PaymentProof.query.filter_by(order_id=order.id).order_by(PaymentProof.id).all()
        data["payment_proofs"] = []
        for proof in proofs:
            asset = db.session.get(MediaAsset, proof.asset_id)
            data["payment_proofs"].append({
                "id": proof.id,
                "asset_id": proof.asset_id,
                "url": asset.url if asset else None,
                "status": proof.status,
                "submitted_by": proof.submitted_by,
                "reviewed_by": proof.reviewed_by,
                "reviewed_at": proof.reviewed_at.isoformat() if proof.reviewed_at else None,
            })

        shipments = Shipment.query.filter_by(order_id=order.id).order_by(Shipment.id).all()
        data["shipments"] = []
        for shipment in shipments:
            events = ShipmentEvent.query.filter_by(shipment_id=shipment.id).order_by(ShipmentEvent.occurred_at, ShipmentEvent.id).all()
            data["shipments"].append({
                "id": shipment.id,
                "shipping_method_id": shipment.shipping_method_id,
                "tracking_no": shipment.tracking_no,
                "status": shipment.status,
                "shipped_at": shipment.shipped_at.isoformat() if shipment.shipped_at else None,
                "delivered_at": shipment.delivered_at.isoformat() if shipment.delivered_at else None,
                "events": [
                    {
                        "status": event.status,
                        "location": event.location,
                        "description": event.description,
                        "occurred_at": event.occurred_at.isoformat() if event.occurred_at else None,
                    }
                    for event in events
                ],
            })

        conversations = Conversation.query.filter_by(order_id=order.id).order_by(Conversation.id).all()
        data["conversations"] = []
        for conversation in conversations:
            messages = Message.query.filter_by(conversation_id=conversation.id).order_by(Message.created_at, Message.id).all()
            data["conversations"].append({
                "id": conversation.id,
                "customer_id": conversation.customer_id,
                "type": conversation.type,
                "subject": conversation.subject,
                "status": conversation.status,
                "last_message_at": conversation.last_message_at.isoformat() if conversation.last_message_at else None,
                "messages": [
                    {
                        "id": message.id,
                        "sender_type": message.sender_type,
                        "sender_id": message.sender_id,
                        "message_type": message.message_type,
                        "body": message.body,
                        "created_at": message.created_at.isoformat() if message.created_at else None,
                        "read_at": message.read_at.isoformat() if message.read_at else None,
                        "attachments": [
                            {
                                "id": attachment.id,
                                "asset_id": attachment.asset_id,
                                "url": (
                                    db.session.get(MediaAsset, attachment.asset_id).url
                                    if db.session.get(MediaAsset, attachment.asset_id)
                                    else None
                                ),
                            }
                            for attachment in MessageAttachment.query.filter_by(message_id=message.id).order_by(MessageAttachment.sort_order, MessageAttachment.id).all()
                        ],
                    }
                    for message in messages
                ],
            })

        data["returns"] = []
        for row in ReturnRequest.query.filter_by(order_id=order.id).order_by(ReturnRequest.id).all():
            data["returns"].append({
                "id": row.id,
                "customer_id": row.customer_id,
                "reason": row.reason,
                "description": row.description,
                "status": row.status,
                "requested_at": row.requested_at.isoformat() if row.requested_at else None,
                "approved_at": row.approved_at.isoformat() if row.approved_at else None,
                "items": [
                    {"order_item_id": item.order_item_id, "qty": item.qty, "condition": item.condition}
                    for item in ReturnItem.query.filter_by(return_request_id=row.id).order_by(ReturnItem.id).all()
                ],
            })

        data["refunds"] = [
            {
                "id": row.id,
                "return_request_id": row.return_request_id,
                "amount": str(row.amount),
                "currency_id": row.currency_id,
                "method": row.method,
                "status": row.status,
                "processed_at": row.processed_at.isoformat() if row.processed_at else None,
            }
            for row in Refund.query.filter_by(order_id=order.id).order_by(Refund.id).all()
        ]

        data["warranty_claims"] = [
            {
                "id": row.id,
                "customer_id": row.customer_id,
                "order_item_id": row.order_item_id,
                "issue": row.issue,
                "description": row.description,
                "status": row.status,
                "resolution": row.resolution,
            }
            for row in WarrantyClaim.query.filter_by(order_id=order.id).order_by(WarrantyClaim.id).all()
        ]

        return data


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
