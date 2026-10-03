from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import and_, or_

from ...extensions import db
from ...models import (
    Cart,
    CartItem,
    City,
    Currency,
    Conversation,
    Customer,
    CustomerAddress,
    Country,
    Region,
    CityArea,
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
    Wallet,
    WalletTransaction,
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
        city = db.session.get(City, address.city_id) if address.city_id else None
        area = db.session.get(CityArea, address.city_area_id) if address.city_area_id else None
        region = db.session.get(Region, city.region_id) if city else None
        country = db.session.get(Country, address.country_id) if address.country_id else None
        return {
            "id": address.id,
            "recipient_name": address.recipient_name,
            "phone": address.phone,
            "country_id": address.country_id,
            "country_name": country.name_ar if country else None,
            "region_id": region.id if region else None,
            "region_name": region.name if region else None,
            "city_id": address.city_id,
            "city_name": city.name if city else None,
            "city_area_id": address.city_area_id,
            "city_area_name": area.name if area else None,
            "district": address.district,
            "street": address.street,
            "landmark": address.landmark,
            "lat": str(address.lat) if address.lat is not None else None,
            "lng": str(address.lng) if address.lng is not None else None,
        }

    @staticmethod
    def _resolve_shipping(customer_id, city_id, area_id, subtotal_sar, fx_rate, method_id=None):
        quote = ShippingService.quote(
            customer_id=customer_id,
            city_id=city_id,
            area_id=area_id,
            subtotal_sar=Decimal(subtotal_sar),
            fx_rate=Decimal(fx_rate),
            method_id=int(method_id) if method_id else None,
        )
        return quote

    @staticmethod
    def create_order(payload):
        customer_id = int(payload["customer_id"])
        address_id = int(payload["address_id"])
        requested_currency_id = payload.get("currency_id")
        # Payment is intentionally selected after the order is created.
        payment_method_id = None
        shipping_method_id = int(payload["shipping_method_id"]) if payload.get("shipping_method_id") else None
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
                        "stock_location_id": stock.location_id,
                        "selected_options": raw.get("selected_options") or raw.get("options") or {},
                    }
                )

            shipping_quote = CommerceService._resolve_shipping(
                customer_id,
                address.city_id,
                address.city_area_id,
                subtotal_sar,
                order_items[0]["price"].fx_rate,
                shipping_method_id,
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
                payment_method_id=None,
                shipping_override=None,
                shipping_override_note=None,
                customer_note=str(payload.get("customer_note") or payload.get("note") or "").strip()[:4000] or None,
                shipping_rule_ids_json=list(shipping_quote.applied_rule_ids or []),
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
                    stock_location_id=item.get("stock_location_id"),
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

            # Customer submission creates a reviewable order.
            # Admin confirmation moves it to awaiting_payment.
            order.status = "created"
            order.payment_status = "unpaid"
            db.session.add(
                OrderStatusHistory(
                    order_id=order.id,
                    from_status=None,
                    to_status=order.status,
                    actor_type="customer",
                    actor_id=customer_id,
                    note="Order created",
                )
            )

        db.session.commit()
        conversation = Conversation.query.filter_by(order_id=order.id).first()
        if conversation is None:
            db.session.add(Conversation(
                customer_id=customer_id,
                order_id=order.id,
                type="order_support",
                subject=f"الطلب {order.order_no}",
                status="open",
                last_message_at=datetime.now(timezone.utc),
            ))
            db.session.commit()
        cart = Cart.query.filter_by(customer_id=customer_id).first()
        if cart is not None:
            CartItem.query.filter_by(cart_id=cart.id).delete(synchronize_session=False)
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
                "selected_options": {
                    option.option_name: option.option_value
                    for option in OrderItemOption.query.filter_by(order_item_id=item.id).order_by(OrderItemOption.id).all()
                },
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
        currency = db.session.get(Currency, order.currency_id) if order.currency_id else None
        payment_method = db.session.get(PaymentMethod, order.payment_method_id) if getattr(order, "payment_method_id", None) else None
        shipping_rate = db.session.get(ShippingRate, order.shipping_rate_id) if order.shipping_rate_id else None
        shipping_method = db.session.get(ShippingMethod, shipping_rate.method_id) if shipping_rate else None
        order_items = (
            OrderItem.query
            .filter_by(order_id=order.id)
            .order_by(OrderItem.id)
            .all()
        )
        previews = []
        for item in order_items[:4]:
            media = (
                ProductMedia.query
                .filter_by(product_id=item.product_id)
                .order_by(ProductMedia.sort_order, ProductMedia.id)
                .first()
                if item.product_id
                else None
            )
            asset = db.session.get(MediaAsset, media.asset_id) if media else None
            previews.append({
                "id": item.id,
                "product_id": item.product_id,
                "name": item.name_snapshot,
                "qty": item.qty,
                "unit_price": str(item.sale_price_display),
                "total": str(item.total),
                "image_url": asset.url if asset else None,
            })

        return {
            "id": order.id,
            "order_no": order.order_no,
            "customer_id": order.customer_id,
            "city_id": order.city_id,
            "currency_id": order.currency_id,
            "currency": {
                "id": currency.id,
                "code": currency.code,
                "symbol": currency.symbol or currency.code,
                "name_ar": currency.name_ar,
            } if currency else None,
            "pricing_group_id": order.pricing_group_id,
            "fx_rate": str(order.fx_rate),
            "subtotal": str(order.subtotal),
            "discount": str(order.discount),
            "shipping": str(order.shipping),
            "shipping_base_sar": str(order.shipping_base_sar),
            "customer_note": order.customer_note,
            "shipping_rule_ids": list(order.shipping_rule_ids_json or []),
            "shipping_rate_id": order.shipping_rate_id,
            "shipping_method_id": shipping_rate.method_id if shipping_rate else None,
            "shipping_method": {
                "id": shipping_method.id,
                "name": shipping_method.name,
                "code": shipping_method.code,
                "supports_cod": bool(shipping_method.supports_cod),
            } if shipping_method else None,
            "total": str(order.total),
            "shipping_override": str(order.shipping_override) if order.shipping_override is not None else None,
            "shipping_override_note": order.shipping_override_note,
            "shipping_configured": bool(order.shipping_rate_id or order.shipping_override is not None),
            "shipping_source": "manual" if order.shipping_override is not None else ("rate" if order.shipping_rate_id else "unconfigured"),
            "customer_feedback": order.customer_feedback,
            "customer_rating": order.customer_rating,
            "status": order.status,
            "payment_status": order.payment_status,
            "shipping_status": order.shipping_status,
            "payment_method_id": getattr(order, "payment_method_id", None),
            "customer_note": order.customer_note,
            "payment_method": ({
                "id": payment_method.id,
                "name": payment_method.name,
                "code": payment_method.code,
                "supports_proof": bool(payment_method.supports_proof),
                "settings": dict(payment_method.settings_json or {}),
            } if payment_method else None),
            "shipping_rules": list(order.shipping_rule_ids_json or []),
            "item_count": sum(int(x.qty or 0) for x in order_items),
            "items_preview": previews,
            "customer_note": order.customer_note,
            "created_at": order.created_at.isoformat() if order.created_at else None,
            "updated_at": order.updated_at.isoformat() if order.updated_at else None,
            "address_snapshot": order.address_snapshot,
        }

    @staticmethod
    def record_customer_payment(order_id, customer_id, method_id, amount=None, currency_id=None):
        order = db.session.get(Order, int(order_id))
        if order is None or order.customer_id != int(customer_id):
            raise LookupError("order not found")
        if order.status != "awaiting_payment":
            raise ValueError("يجب اعتماد الطلب من المتجر أولًا قبل الدفع.")
        if not (order.shipping_rate_id or order.shipping_override is not None):
            raise ValueError("لم يتم تحديد رسوم التوصيل لهذا الطلب بعد.")
        method = db.session.get(PaymentMethod, int(method_id))
        if method is None or not method.is_active:
            raise ValueError("طريقة الدفع غير متاحة.")
        amount = Decimal(str(amount if amount not in (None, "") else order.total))
        if amount != Decimal(order.total):
            raise ValueError("يجب دفع إجمالي الطلب كاملًا.")
        currency_id = int(currency_id or order.currency_id)
        settings = dict(method.settings_json or {})
        method_type = str(settings.get("type") or method.code).strip().lower()
        if method.code == "wallet" or method_type == "wallet":
            return CommerceService.pay_order_from_wallet(order.id, customer_id)

        order.payment_method_id = method.id
        transaction = (
            PaymentTransaction.query
            .filter_by(order_id=order.id, status="pending")
            .order_by(PaymentTransaction.id.desc())
            .first()
        )
        if transaction is None:
            transaction = PaymentTransaction(
                order_id=order.id,
                method_id=method.id,
                amount=amount,
                currency_id=currency_id,
                provider_ref="CUSTOMER-" + uuid4().hex[:10].upper(),
                status="cod_pending" if method_type == "cod" else "pending",
            )
            db.session.add(transaction)
        else:
            transaction.method_id = method.id
            transaction.amount = amount
            transaction.currency_id = currency_id
        if method_type == "cod":
            order.payment_status = "cod"
            previous = order.status
            order.status = "processing"
            db.session.add(OrderStatusHistory(
                order_id=order.id,
                from_status=previous,
                to_status="processing",
                actor_type="customer",
                actor_id=customer_id,
                note="اختار العميل الدفع عند الاستلام",
            ))
            transaction.status = "cod_pending"
            db.session.commit()
            return {
                "order_id": order.id,
                "transaction_id": transaction.id,
                "status": "cod",
                "payment_status": "cod",
                "order_status": "processing",
                "method": {
                    "id": method.id,
                    "name": method.name,
                    "code": method.code,
                    "settings": settings,
                    "supports_proof": False,
                },
            }

        order.payment_status = "pending"
        order.status = "awaiting_payment"
        db.session.commit()
        return {
            "order_id": order.id,
            "transaction_id": transaction.id,
            "status": transaction.status,
            "payment_status": order.payment_status,
            "method": {
                "id": method.id,
                "name": method.name,
                "code": method.code,
                "settings": settings,
                "supports_proof": bool(method.supports_proof),
            },
        }

    @staticmethod
    def pay_order_from_wallet(order_id, customer_id):
        order = db.session.get(Order, int(order_id))
        if order is None or order.customer_id != int(customer_id):
            raise LookupError("order not found")
        if order.status != "awaiting_payment":
            raise ValueError("يجب اعتماد الطلب من المتجر أولًا قبل الدفع.")
        if not (order.shipping_rate_id or order.shipping_override is not None):
            raise ValueError("لم يتم تحديد رسوم التوصيل لهذا الطلب بعد.")
        from ...models import Currency
        currency = db.session.get(Currency, order.currency_id)
        if currency is None:
            raise LookupError("عملة الطلب غير موجودة.")
        wallet = (
            Wallet.query
            .filter_by(customer_id=customer_id, currency_id=order.currency_id, status="active", is_active=True)
            .with_for_update()
            .first()
        )
        if wallet is None or Decimal(wallet.balance) < Decimal(order.total):
            raise ValueError("رصيدك غير كافٍ لإتمام الدفع.")
        method = PaymentMethod.query.filter_by(code="wallet").first()
        if method is None:
            method = PaymentMethod(
                name="الدفع من الرصيد",
                code="wallet",
                provider="internal_wallet",
                supports_proof=False,
                settings_json={"type": "wallet"},
            )
            db.session.add(method)
            db.session.flush()

        wallet.balance = Decimal(wallet.balance) - Decimal(order.total)
        db.session.add(WalletTransaction(
            wallet_id=wallet.id,
            type="order_payment",
            amount=-Decimal(order.total),
            currency_id=order.currency_id,
            reference_type="order",
            reference_id=order.id,
            balance_after=wallet.balance,
        ))
        tx = PaymentTransaction(
            order_id=order.id,
            method_id=method.id,
            amount=Decimal(order.total),
            currency_id=order.currency_id,
            provider_ref="WALLET-" + uuid4().hex[:10].upper(),
            status="paid",
            paid_at=datetime.now(timezone.utc),
        )
        db.session.add(tx)
        order.payment_method_id = method.id
        order.payment_status = "paid"
        previous = order.status
        order.status = "processing"
        db.session.add(OrderStatusHistory(
            order_id=order.id,
            from_status=previous,
            to_status="processing",
            actor_type="customer",
            actor_id=customer_id,
            note="Paid from customer wallet",
        ))
        db.session.commit()
        return {
            "order_id": order.id,
            "transaction_id": tx.id,
            "status": "paid",
            "payment_status": "paid",
            "order_status": "processing",
            "wallet_balance": str(wallet.balance),
        }

    @staticmethod
    def set_shipping_override(order_id, amount, note=None, actor_id=None):
        order = db.session.get(Order, int(order_id))
        if order is None:
            raise LookupError("order not found")
        if order.status in {"shipped", "delivered", "returned", "cancelled"}:
            raise ValueError("لا يمكن تعديل رسوم الشحن بعد بدء التسليم.")
        value = Decimal(str(amount))
        if value < 0:
            raise ValueError("رسوم الشحن لا يمكن أن تكون سالبة.")
        order.shipping_override = value
        order.shipping_override_note = (str(note or "").strip()[:1000] or None)
        order.shipping = value
        order.shipping_base_sar = (
            value / Decimal(order.fx_rate) if Decimal(order.fx_rate or 0) != 0 else value
        )
        order.total = Decimal(order.subtotal) - Decimal(order.discount or 0) + value
        db.session.add(OrderStatusHistory(
            order_id=order.id,
            from_status=order.status,
            to_status=order.status,
            actor_type="admin",
            actor_id=actor_id,
            note="تعيين/تعديل رسوم التوصيل يدويًا",
        ))
        db.session.commit()
        return CommerceService.serialize_order_detail(order)

    @staticmethod
    def save_customer_feedback(order_id, customer_id, rating=None, feedback=None):
        order = db.session.get(Order, int(order_id))
        if order is None or order.customer_id != int(customer_id):
            raise LookupError("order not found")
        if order.status != "delivered":
            raise ValueError("يمكن تقييم الطلب بعد تسليمه.")
        if rating not in (None, ""):
            rating = int(rating)
            if rating < 1 or rating > 5:
                raise ValueError("التقييم من 1 إلى 5.")
            order.customer_rating = rating
        if feedback is not None:
            order.customer_feedback = str(feedback).strip()[:4000] or None
        db.session.commit()
        return {
            "order_id": order.id,
            "rating": order.customer_rating,
            "feedback": order.customer_feedback,
        }

    @staticmethod
    def update_pending_order(order_id, customer_id, payload):
        order=db.session.get(Order,int(order_id))
        if order is None or order.customer_id != int(customer_id): raise LookupError("order not found")
        if order.status not in {"created","awaiting_payment"}: raise ValueError("لا يمكن تعديل الطلب بعد تأكيده أو بدء معالجته.")
        address_id=payload.get("address_id")
        if address_id:
            address=db.session.get(CustomerAddress,int(address_id))
            if address is None or address.customer_id!=order.customer_id or not address.is_active: raise ValueError("عنوان التوصيل غير صالح.")
        else:
            address=db.session.get(CustomerAddress,(order.address_snapshot or {}).get("id"))
        if address is None: raise ValueError("تعذر تحديد عنوان الطلب.")
        raw_items=payload.get("items") or []
        if not raw_items: raise ValueError("الطلب يجب أن يحتوي على منتج واحد على الأقل.")
        requested=[]
        for raw in raw_items:
            item=db.session.get(OrderItem,int(raw.get("order_item_id") or raw.get("id") or 0))
            if item is None or item.order_id!=order.id: raise ValueError("عنصر الطلب غير صالح.")
            qty=int(raw.get("qty",item.qty))
            if qty<1: raise ValueError("الكمية يجب أن تكون 1 أو أكثر.")
            requested.append((item,qty,raw.get("selected_options") or raw.get("options") or {}))
        for item,new_qty,_ in requested:
            delta=new_qty-int(item.qty)
            if delta>0:
                rows=(StockInventory.query.join(InventoryLocation,InventoryLocation.id==StockInventory.location_id).filter(StockInventory.variant_id==item.variant_id,StockInventory.available>=delta,InventoryLocation.is_active.is_(True)).with_for_update().order_by(InventoryLocation.city_id.isnot(address.city_id),StockInventory.available.desc()).all())
                if not rows: raise ValueError("الكمية المطلوبة غير متوفرة.")
                rows[0].reserved+=delta; rows[0].available=rows[0].on_hand-rows[0].reserved
            elif delta<0:
                remaining=-delta
                for stock in StockInventory.query.filter_by(variant_id=item.variant_id).with_for_update().all():
                    release=min(remaining,int(stock.reserved or 0))
                    if release: stock.reserved-=release; stock.available=stock.on_hand-stock.reserved; remaining-=release
                    if remaining<=0: break
        by_id={x.id:(q,o) for x,q,o in requested}
        currency_id=int(payload.get("currency_id") or order.currency_id); subtotal=Decimal("0"); subtotal_sar=Decimal("0"); last_price=None; last_context=None
        for item in OrderItem.query.filter_by(order_id=order.id).order_by(OrderItem.id).all():
            qty,opts=by_id.get(item.id,(item.qty,None)); product=db.session.get(Product,item.product_id)
            ctx,price=price_for_customer(base_price_sar=Decimal(product.base_price),customer_id=order.customer_id,city_id=address.city_id,currency_id=currency_id); last_price=price; last_context=ctx
            item.qty=qty; item.base_price_sar=price.base_sar; item.fx_rate=price.fx_rate; item.markup_percent=ctx.override_percent if ctx.override_percent is not None else ctx.rule.percent_markup; item.markup_fixed=ctx.override_fixed if ctx.override_fixed is not None else ctx.rule.fixed_markup; item.sale_price_display=price.final; item.total=price.final*qty
            if isinstance(opts,dict):
                OrderItemOption.query.filter_by(order_item_id=item.id).delete()
                for k,v in opts.items():
                    if str(k).strip() and str(v).strip(): db.session.add(OrderItemOption(order_item_id=item.id,option_name=str(k).strip()[:120],option_value=str(v).strip()[:160]))
            subtotal+=item.total; subtotal_sar+=price.base_sar*qty
        quote=ShippingService.quote(customer_id=order.customer_id,city_id=address.city_id,area_id=address.city_area_id,subtotal_sar=subtotal_sar,fx_rate=last_price.fx_rate)
        order.address_snapshot=CommerceService._address_snapshot(address); order.city_id=address.city_id; order.currency_id=currency_id; order.fx_rate=last_price.fx_rate; order.subtotal=subtotal; order.shipping=quote.price_display; order.shipping_base_sar=quote.price_sar; order.shipping_rate_id=quote.rate_id; order.shipping_rule_ids_json=list(quote.applied_rule_ids or []); order.total=subtotal+quote.price_display; order.customer_note=str(payload.get("customer_note") or payload.get("note") or order.customer_note or "").strip()[:4000] or None
        order.payment_status="unpaid"; order.status="created"; db.session.commit(); return CommerceService.serialize_order_detail(order)

    @staticmethod
    def update_customer_order(customer_id, order_id, payload):
        order = db.session.get(Order, int(order_id))
        if order is None or order.customer_id != int(customer_id):
            raise LookupError("order not found")
        if order.status != "created":
            raise ValueError("يمكن تعديل الطلب من قبل العميل قبل تأكيد المتجر فقط.")
        items = payload.get("items") or []
        if not items:
            raise ValueError("يجب أن يحتوي الطلب على منتج واحد على الأقل.")

        address = None
        if payload.get("address_id"):
            address = db.session.get(CustomerAddress, int(payload["address_id"]))
        if address is None:
            saved = order.address_snapshot or {}
            if saved.get("id"):
                address = db.session.get(CustomerAddress, int(saved["id"]))
        if address is None or address.customer_id != int(customer_id) or address.city_id is None:
            raise ValueError("عنوان الشحن غير صالح.")

        old_items = OrderItem.query.filter_by(order_id=order.id).all()
        with db.session.begin_nested():
            for old in old_items:
                stock = None
                if old.stock_location_id and old.variant_id:
                    stock = (
                        StockInventory.query
                        .filter_by(
                            location_id=old.stock_location_id,
                            variant_id=old.variant_id,
                        )
                        .with_for_update()
                        .first()
                    )
                if stock is None and old.variant_id:
                    stock = (
                        StockInventory.query
                        .filter_by(variant_id=old.variant_id)
                        .join(InventoryLocation, InventoryLocation.id == StockInventory.location_id)
                        .filter(InventoryLocation.is_active.is_(True))
                        .order_by(StockInventory.reserved.desc(), StockInventory.id.desc())
                        .with_for_update()
                        .first()
                    )
                if stock is not None:
                    stock.reserved = max(0, int(stock.reserved or 0) - int(old.qty or 0))
                    stock.available = int(stock.on_hand or 0) - int(stock.reserved or 0)

            old_ids = [x.id for x in old_items]
            if old_ids:
                OrderItemOption.query.filter(OrderItemOption.order_item_id.in_(old_ids)).delete(synchronize_session=False)
                for old in old_items:
                    db.session.delete(old)
                db.session.flush()

            subtotal = Decimal("0")
            subtotal_sar = Decimal("0")
            first_price = None
            first_context = None

            for raw in items:
                variant_id = int(raw["variant_id"])
                qty = int(raw.get("qty", 1))
                if qty <= 0:
                    raise ValueError("الكمية يجب أن تكون أكبر من صفر.")
                variant = db.session.get(ProductVariant, variant_id)
                product = db.session.get(Product, variant.product_id) if variant else None
                if (
                    variant is None or product is None
                    or not variant.is_active
                    or not product.is_active
                    or product.status != "published"
                ):
                    raise ValueError("أحد المنتجات أو الاختيارات لم يعد متاحًا.")

                context, price = price_for_customer(
                    base_price_sar=Decimal(product.base_price),
                    customer_id=customer_id,
                    city_id=address.city_id,
                    currency_id=order.currency_id,
                )
                if first_price is None:
                    first_price, first_context = price, context
                subtotal += price.final * qty
                subtotal_sar += price.base_sar * qty

                stock_rows = (
                    StockInventory.query
                    .join(InventoryLocation, InventoryLocation.id == StockInventory.location_id)
                    .filter(
                        StockInventory.variant_id == variant_id,
                        StockInventory.available >= qty,
                        InventoryLocation.is_active.is_(True),
                    )
                    .with_for_update()
                    .order_by(
                        InventoryLocation.city_id.isnot(address.city_id),
                        StockInventory.available.desc(),
                    )
                    .all()
                )
                if not stock_rows:
                    raise ValueError("المخزون غير كافٍ لأحد المنتجات.")
                stock = stock_rows[0]
                stock.reserved += qty
                stock.available = stock.on_hand - stock.reserved

                order_item = OrderItem(
                    order_id=order.id,
                    product_id=product.id,
                    variant_id=variant.id,
                    stock_location_id=stock.location_id,
                    sku_snapshot=variant.sku,
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
                    qty=qty,
                    total=price.final * qty,
                )
                db.session.add(order_item)
                db.session.flush()

                selected_options = raw.get("selected_options") or raw.get("options") or {}
                if isinstance(selected_options, dict):
                    selected_options = [{"name": k, "value": v} for k, v in selected_options.items()]
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

            selected_shipping_method_id = (
                int(payload["shipping_method_id"])
                if payload.get("shipping_method_id")
                else None
            )
            if selected_shipping_method_id is None and order.shipping_rate_id:
                previous_rate = db.session.get(ShippingRate, order.shipping_rate_id)
                selected_shipping_method_id = previous_rate.method_id if previous_rate else None
            shipping_quote = CommerceService._resolve_shipping(
                customer_id,
                address.city_id,
                address.city_area_id,
                subtotal_sar,
                first_price.fx_rate if first_price else order.fx_rate,
                selected_shipping_method_id,
            )
            order.address_snapshot = CommerceService._address_snapshot(address)
            order.city_id = address.city_id
            order.currency_id = first_context.currency_id if first_context else order.currency_id
            order.pricing_group_id = first_context.pricing_group_id if first_context else order.pricing_group_id
            order.fx_rate = first_price.fx_rate if first_price else order.fx_rate
            order.subtotal = subtotal
            order.shipping = shipping_quote.price_display
            order.shipping_base_sar = shipping_quote.price_sar
            order.shipping_rate_id = shipping_quote.rate_id
            order.shipping_rule_ids_json = list(shipping_quote.applied_rule_ids or [])
            order.total = subtotal + shipping_quote.price_display
            order.shipping_override = None
            order.shipping_override_note = None
            if "customer_note" in payload:
                order.customer_note = str(payload.get("customer_note") or "").strip()[:4000] or None

            transaction = (
                PaymentTransaction.query
                .filter_by(order_id=order.id)
                .filter(PaymentTransaction.status.in_(("pending", "cod_pending")))
                .order_by(PaymentTransaction.id.desc())
                .first()
            )
            if transaction:
                transaction.amount = order.total
                transaction.currency_id = order.currency_id

            db.session.add(OrderStatusHistory(
                order_id=order.id,
                from_status=order.status,
                to_status=order.status,
                actor_type="customer",
                actor_id=int(customer_id),
                note="Customer edited order",
            ))

        db.session.commit()
        return CommerceService.serialize_order_detail(order)

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
        if to_status == "awaiting_payment":
            order.payment_status = "unpaid"
            if order.shipping_override is None and not order.shipping_rate_id:
                item_rows = OrderItem.query.filter_by(order_id=order.id).all()
                subtotal_sar = sum(
                    (Decimal(item.base_price_sar or 0) * int(item.qty or 0))
                    for item in item_rows
                )
                address = (order.address_snapshot or {})
                quote = CommerceService._resolve_shipping(
                    order.customer_id,
                    order.city_id or address.get("city_id"),
                    address.get("city_area_id"),
                    subtotal_sar,
                    Decimal(order.fx_rate or 1),
                    None,
                )
                if quote.rate_id is not None:
                    order.shipping = quote.price_display
                    order.shipping_base_sar = quote.price_sar
                    order.shipping_rate_id = quote.rate_id
                    order.shipping_rule_ids_json = list(quote.applied_rule_ids or [])
                    order.total = Decimal(order.subtotal) - Decimal(order.discount or 0) + quote.price_display
        with db.session.begin_nested():
            items = OrderItem.query.filter_by(order_id=order.id).all()
            if to_status == "cancelled":
                for item in items:
                    if not item.variant_id:
                        continue
                    stocks = StockInventory.query.filter_by(
                        variant_id=item.variant_id,
                    ).with_for_update().all()
                    remaining = int(item.qty or 0)
                    for stock in stocks:
                        released = min(remaining, int(stock.reserved or 0))
                        if released:
                            stock.reserved = int(stock.reserved or 0) - released
                            stock.available = int(stock.on_hand or 0) - int(stock.reserved or 0)
                            remaining -= released
                        if remaining <= 0:
                            break
            elif to_status == "shipped":
                for item in items:
                    if not item.variant_id:
                        continue
                    stock = None
                    if item.stock_location_id:
                        stock = StockInventory.query.filter_by(
                            variant_id=item.variant_id,
                            location_id=item.stock_location_id,
                        ).with_for_update().first()
                    if stock is None:
                        stock = StockInventory.query.filter_by(
                            variant_id=item.variant_id,
                        ).order_by(StockInventory.reserved.desc(), StockInventory.id.desc()).with_for_update().first()
                    if stock is None:
                        raise ValueError("مخزون عنصر الطلب غير موجود.")
                    qty = int(item.qty or 0)
                    if int(stock.reserved or 0) < qty or int(stock.on_hand or 0) < qty:
                        raise ValueError("لا يمكن شحن كمية غير محجوزة من المخزون.")
                    stock.reserved = int(stock.reserved or 0) - qty
                    stock.on_hand = int(stock.on_hand or 0) - qty
                    stock.available = int(stock.on_hand or 0) - int(stock.reserved or 0)

            order.status = to_status
            db.session.add(OrderStatusHistory(
                order_id=order.id,
                from_status=previous,
                to_status=to_status,
                actor_type=actor_type,
                actor_id=actor_id,
                note=note,
            ))
        db.session.commit()

        message_by_status = {
            "awaiting_payment": (
                "تم تأكيد طلبك من المتجر. أصبح الطلب بانتظار الدفع ويمكنك اختيار طريقة الدفع من صفحة الطلب."
                if order.shipping_rate_id or order.shipping_override is not None
                else "تم تأكيد طلبك من المتجر، لكن رسوم التوصيل لم تُحدد بعد. سيحدث الدفع بعد تحديدها."
            ),
            "processing": "بدأ المتجر تجهيز طلبك.",
            "shipped": "تم شحن طلبك وبدأت رحلة التوصيل.",
            "delivered": "تم تسليم طلبك بنجاح. شكرًا لاختيار التخفيض الصح.",
            "cancelled": "تم إلغاء الطلب. يمكنك التواصل مع خدمة العملاء عند الحاجة.",
            "returned": "تم تسجيل إرجاع الطلب.",
        }
        message = message_by_status.get(to_status)
        if message:
            conversation = Conversation.query.filter_by(order_id=order.id).order_by(Conversation.id.desc()).first()
            if conversation is None:
                conversation = Conversation(
                    customer_id=order.customer_id,
                    order_id=order.id,
                    type="order_support",
                    subject="الطلب " + order.order_no,
                    status="open",
                )
                db.session.add(conversation)
                db.session.flush()
            db.session.add(Message(
                conversation_id=conversation.id,
                sender_type="admin",
                sender_id=int(actor_id or 0),
                message_type="text",
                body=message,
            ))
            conversation.last_message_at = db.func.now()
            db.session.commit()

        return CommerceService.serialize_order(order)

    @staticmethod
    def add_to_cart(customer_id, variant_id, qty=1, selected_options=None):
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
        normalized_options = selected_options if isinstance(selected_options, dict) else {}
        candidates = CartItem.query.filter_by(cart_id=cart.id, variant_id=variant_id).all()
        item = next((x for x in candidates if dict(x.selected_options or {}) == dict(normalized_options)), None)
        if item:
            item.qty += qty
        else:
            item = CartItem(cart_id=cart.id, variant_id=variant_id, qty=qty, selected_options=normalized_options)
            db.session.add(item)
        db.session.commit()
        return {"cart_id": cart.id, "variant_id": variant_id, "qty": item.qty}
