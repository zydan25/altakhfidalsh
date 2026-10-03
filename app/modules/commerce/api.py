from decimal import Decimal

from flask import request

from . import api_bp
from ...security import admin_api_required
from ..customer.security import customer_required, current_customer
from .services import CommerceService
from ...services.pricing import resolve_exchange_rate
from ...services.shipping import ShippingService
from ...extensions import db
from ...models import Order, PaymentTransaction, PaymentProof


@api_bp.get("/orders")
@admin_api_required("order.view")
def orders():
    page = max(request.args.get("page", 1, type=int), 1)
    per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
    status = request.args.get("status")
    query = Order.query
    if status:
        query = query.filter(Order.status == status)
    pagination = query.order_by(Order.id.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return {
        "items": [CommerceService.serialize_order(x) for x in pagination.items],
        "pagination": {
            "page": pagination.page,
            "per_page": pagination.per_page,
            "pages": pagination.pages,
            "total": pagination.total,
        },
    }


@api_bp.get("/orders/<int:order_id>")
@admin_api_required("order.view")
def order(order_id):
    item = db.session.get(Order, order_id)
    if item is None:
        return {"error": "not_found"}, 404
    return {"item": CommerceService.serialize_order(item)}


@api_bp.post("/orders")
@customer_required
def create_order():
    payload = request.get_json(silent=True) or {}
    payload["customer_id"] = current_customer().id
    try:
        return {"item": CommerceService.create_order(payload)}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "order_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/orders/<int:order_id>/detail")
@admin_api_required("order.view")
def order_detail(order_id):
    item = db.session.get(Order, order_id)
    if item is None:
        return {"error": "not_found"}, 404
    return {"item": CommerceService.serialize_order_detail(item)}


@api_bp.patch("/orders/<int:order_id>/shipping-fee")
@admin_api_required("order.manage")
def set_order_shipping_fee(order_id):
    payload = request.get_json(silent=True) or {}
    try:
        amount = payload["amount"]
        return {"item": CommerceService.set_shipping_override(
            order_id,
            amount,
            payload.get("note"),
            request.args.get("admin_id", type=int),
        )}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "shipping_fee_update_failed", "detail": str(exc)}, 400


@api_bp.post("/orders/<int:order_id>/status")
@admin_api_required("order.manage")
def transition_order(order_id):
    payload = request.get_json(silent=True) or {}
    try:
        item = CommerceService.transition_order(
            order_id,
            str(payload["status"]),
            actor_type=str(payload.get("actor_type", "admin")),
            actor_id=payload.get("actor_id"),
            note=payload.get("note"),
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "status_change_failed", "detail": str(exc)}, 400
    return {"item": item}


@api_bp.post("/cart/items")
@customer_required
def cart_item():
    payload = request.get_json(silent=True) or {}
    try:
        item = CommerceService.add_to_cart(
            int(payload["customer_id"]),
            int(payload["variant_id"]),
            int(payload.get("qty", 1)),
            payload.get("selected_options") or payload.get("options") or {},
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_update_failed", "detail": str(exc)}, 400
    return {"item": item}, 201


from .payment_shipping import PaymentShippingService


@api_bp.get("/payment-methods")
def payment_methods():
    from ...models import PaymentMethod
    PaymentShippingService.ensure_default_payment_methods()
    rows = PaymentMethod.query.filter_by(is_active=True).order_by(PaymentMethod.id).all()
    return {"items": [{"id": x.id, "name": x.name, "code": x.code, "provider": x.provider, "supports_proof": x.supports_proof, "settings": dict(x.settings_json or {})} for x in rows]}


@api_bp.post("/payment-methods")
@admin_api_required("payment.manage")
def create_payment_method():
    try:
        return {"item": PaymentShippingService.create_payment_method(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "payment_method_failed", "detail": str(exc)}, 400


@api_bp.post("/payments")
@admin_api_required("payment.manage")
def record_payment():
    try:
        return {"item": PaymentShippingService.record_payment(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "payment_failed", "detail": str(exc)}, 400


@api_bp.post("/payments/proofs")
@customer_required
def payment_proof():
    payload = request.get_json(silent=True) or {}
    try:
        order_id = int(payload["order_id"])
        order = db.session.get(Order, order_id)
        if order is None or order.customer_id != current_customer().id:
            return {"error": "not_found"}, 404
        payload["submitted_by"] = current_customer().id
        return {"item": PaymentShippingService.attach_payment_proof(payload)}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "payment_proof_failed", "detail": str(exc)}, 400


@api_bp.post("/shipping/quote")
@customer_required
def shipping_quote():
    payload = request.get_json(silent=True) or {}
    try:
        customer = current_customer()
        city_id = int(payload["city_id"]) if payload.get("city_id") else customer.city_id
        area_id = int(payload["city_area_id"]) if payload.get("city_area_id") else customer.city_area_id
        currency_id = int(payload["currency_id"]) if payload.get("currency_id") else None
        method_id = int(payload["shipping_method_id"]) if payload.get("shipping_method_id") else None
        subtotal_sar = Decimal(str(payload.get("subtotal_sar", "0")))
        if subtotal_sar < 0:
            raise ValueError("subtotal_sar cannot be negative")
        if currency_id is None:
            from ...models import PricingGroup
            from ...services.pricing import resolve_pricing_context
            ctx = resolve_pricing_context(customer_id=customer.id, city_id=city_id, area_id=area_id)
            currency_id = ctx.currency_id
        from ...models import Currency
        sar = Currency.query.filter_by(code="SAR", is_active=True).first()
        if sar is None:
            raise LookupError("SAR base currency is not configured")
        fx = resolve_exchange_rate(base_currency_id=sar.id, quote_currency_id=currency_id)
        quote = ShippingService.quote(
            customer_id=customer.id,
            city_id=city_id,
            area_id=area_id,
            subtotal_sar=subtotal_sar,
            currency_id=currency_id,
            fx_rate=fx,
            method_id=method_id,
        )
        return {"item": {
            "configured": quote.rate_id is not None,
            "rate_id": quote.rate_id,
            "method_id": quote.method_id,
            "method_name": quote.method_name,
            "price_sar": str(quote.price_sar),
            "price_display": str(quote.price_display),
            "free": quote.free,
            "source": quote.source,
            "currency_id": currency_id,
            "fx_rate": str(fx),
            "min_order_sar": str(quote.min_order_sar) if quote.min_order_sar is not None else None,
            "max_order_sar": str(quote.max_order_sar) if quote.max_order_sar is not None else None,
            "free_over_sar": str(quote.free_over_sar) if quote.free_over_sar is not None else None,
            "free_shipping_threshold_sar": (
                str(quote.free_shipping_threshold_sar)
                if quote.free_shipping_threshold_sar is not None
                else None
            ),
            "next_benefit_type": quote.next_benefit_type,
            "next_benefit_threshold_sar": (
                str(quote.next_benefit_threshold_sar)
                if quote.next_benefit_threshold_sar is not None
                else None
            ),
            "next_benefit_value": (
                str(quote.next_benefit_value)
                if quote.next_benefit_value is not None
                else None
            ),
            "base_price_sar": str(quote.base_price_sar),
            "adjustment_sar": str(quote.adjustment_sar),
            "applied_rule_ids": list(quote.applied_rule_ids),
        }}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "shipping_quote_failed", "detail": str(exc)}, 400


@api_bp.get("/shipping-methods")
def shipping_methods():
    from ...models import ShippingMethod
    rows = ShippingMethod.query.filter_by(is_active=True).order_by(ShippingMethod.id).all()
    return {"items": [{"id": x.id, "name": x.name, "code": x.code, "supports_cod": x.supports_cod, "delivery_days_min": x.delivery_days_min, "delivery_days_max": x.delivery_days_max} for x in rows]}


@api_bp.post("/shipping-methods")
@admin_api_required("shipping.manage")
def create_shipping_method():
    try:
        return {"item": PaymentShippingService.create_shipping_method(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "shipping_method_failed", "detail": str(exc)}, 400


@api_bp.post("/shipments")
@admin_api_required("shipping.manage")
def create_shipment():
    try:
        return {"item": PaymentShippingService.create_shipment(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "shipment_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/shipments/<int:shipment_id>/events")
@admin_api_required("shipping.manage")
def shipment_event(shipment_id):
    try:
        return {"item": PaymentShippingService.add_shipment_event(shipment_id, request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "shipment_event_failed", "detail": str(exc)}, 400


from .cart import CartService


@api_bp.get("/cart/<int:customer_id>")
@customer_required
def get_cart(customer_id):
    if customer_id != current_customer().id:
        return {"error": "forbidden"}, 403
    try:
        return {"item": CartService.get_cart(customer_id, request.args.get("currency_id", type=int))}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_read_failed", "detail": str(exc)}, 400


@api_bp.patch("/cart/<int:customer_id>/items/<int:item_id>")
@customer_required
def update_cart_item(customer_id, item_id):
    if customer_id != current_customer().id:
        return {"error": "forbidden"}, 403
    payload = request.get_json(silent=True) or {}
    try:
        qty = int(payload["qty"])
        return {"item": CartService.set_item_qty(customer_id, item_id, qty)}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_update_failed", "detail": str(exc)}, 400


@api_bp.delete("/cart/<int:customer_id>/items/<int:item_id>")
@customer_required
def remove_cart_item(customer_id, item_id):
    if customer_id != current_customer().id:
        return {"error": "forbidden"}, 403
    try:
        return {"item": CartService.remove_item(customer_id, item_id)}
    except LookupError as exc:
        return {"error": "cart_item_not_found", "detail": str(exc)}, 404


@api_bp.delete("/cart/<int:customer_id>")
@customer_required
def clear_cart(customer_id):
    if customer_id != current_customer().id:
        return {"error": "forbidden"}, 403
    return {"item": CartService.clear_cart(customer_id)}


@api_bp.get("/me/orders")
@customer_required
def my_orders():
    from ...models import Order
    rows = Order.query.filter_by(customer_id=current_customer().id).order_by(Order.id.desc()).limit(200).all()
    return {"items": [CommerceService.serialize_order(x) for x in rows]}


@api_bp.get("/me/wallet")
@customer_required
def my_wallet():
    from ...models import Wallet, Currency
    customer = current_customer()
    currency_id = request.args.get("currency_id", type=int)
    if currency_id is None:
        from ...services.pricing import resolve_pricing_context
        try:
            currency_id = resolve_pricing_context(customer_id=customer.id).currency_id
        except Exception:
            currency_id = None
    wallet = (
        Wallet.query.filter_by(customer_id=customer.id, currency_id=currency_id, status="active", is_active=True).first()
        if currency_id
        else None
    )
    currency = db.session.get(Currency, currency_id) if currency_id else None
    return {"item": {
        "wallet_id": wallet.id if wallet else None,
        "currency_id": currency_id,
        "currency_code": currency.code if currency else None,
        "currency_symbol": (currency.symbol or currency.code) if currency else None,
        "balance": str(wallet.balance) if wallet else "0",
    }}


@api_bp.post("/me/orders/<int:order_id>/pay-with-wallet")
@customer_required
def customer_order_wallet_payment(order_id):
    try:
        return {"item": CommerceService.pay_order_from_wallet(order_id, current_customer().id)}
    except (ValueError, LookupError) as exc:
        return {"error": "wallet_payment_failed", "detail": str(exc)}, 400


@api_bp.post("/me/orders/<int:order_id>/feedback")
@customer_required
def customer_order_feedback(order_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CommerceService.save_customer_feedback(
            order_id,
            current_customer().id,
            payload.get("rating"),
            payload.get("feedback"),
        )}
    except (ValueError, LookupError) as exc:
        return {"error": "feedback_failed", "detail": str(exc)}, 400


@api_bp.post("/me/orders/<int:order_id>/payment")
@customer_required
def customer_order_payment(order_id):
    payload=request.get_json(silent=True) or {}
    try:
        return {"item": CommerceService.record_customer_payment(order_id,current_customer().id,int(payload["method_id"]),payload.get("amount"),payload.get("currency_id"))}
    except (KeyError,ValueError,LookupError) as exc: return {"error":"payment_failed","detail":str(exc)},400

@api_bp.post("/me/orders/<int:order_id>/payment-proof")
@customer_required
def customer_order_payment_proof(order_id):
    order=db.session.get(Order,order_id)
    if order is None or order.customer_id!=current_customer().id: return {"error":"not_found"},404
    files=request.files.getlist("files")
    if not files: return {"error":"payment_proof_missing","detail":"ارفع صورة إثبات الدفع."},400
    try:
        from ..catalog.services import MediaService
        assets=MediaService.save_generic_files(files[:3],f"payment-proofs/{order.id}")
        tx=PaymentTransaction.query.filter(PaymentTransaction.order_id==order.id,PaymentTransaction.status=="pending").order_by(PaymentTransaction.id.desc()).first()
        proof=PaymentProof(order_id=order.id,transaction_id=tx.id if tx else None,asset_id=assets[0]["id"],submitted_by=current_customer().id,status="pending")
        db.session.add(proof); db.session.commit()
        return {"item":{"id":proof.id,"status":proof.status,"url":assets[0]["url"]}},201
    except (ValueError,LookupError) as exc: db.session.rollback(); return {"error":"payment_proof_failed","detail":str(exc)},400

@api_bp.get("/me/orders/<int:order_id>")
@customer_required
def my_order(order_id):
    order = db.session.get(Order, order_id)
    if order is None or order.customer_id != current_customer().id:
        return {"error": "not_found"}, 404
    return {"item": CommerceService.serialize_order(order)}


@api_bp.get("/me/orders/<int:order_id>/detail")
@customer_required
def my_order_detail(order_id):
    order = db.session.get(Order, order_id)
    if order is None or order.customer_id != current_customer().id:
        return {"error": "not_found"}, 404
    return {"item": CommerceService.serialize_order_detail(order)}


@api_bp.patch("/me/orders/<int:order_id>")
@customer_required
def update_my_order(order_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CommerceService.update_customer_order(
            current_customer().id,
            order_id,
            payload,
        )}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "order_update_failed", "detail": str(exc)}, 400


@api_bp.post("/me/orders/<int:order_id>/cancel")
@customer_required
def cancel_my_order(order_id):
    try:
        return {"item": CommerceService.cancel_customer_order(
            current_customer().id,
            order_id,
        )}
    except (ValueError, LookupError) as exc:
        return {"error": "order_cancel_failed", "detail": str(exc)}, 400


@api_bp.post("/me/cart/items")
@customer_required
def my_cart_item():
    payload = request.get_json(silent=True) or {}
    try:
        item = CommerceService.add_to_cart(
            current_customer().id,
            int(payload["variant_id"]),
            int(payload.get("qty", 1)),
            payload.get("selected_options") or payload.get("options") or {},
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_update_failed", "detail": str(exc)}, 400
    return {"item": item}, 201


@api_bp.patch("/me/cart/items/<int:item_id>")
@customer_required
def update_my_cart_item(item_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CartService.set_item_qty(current_customer().id, item_id, int(payload["qty"]))}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_update_failed", "detail": str(exc)}, 400

@api_bp.delete("/me/cart/items/<int:item_id>")
@customer_required
def remove_my_cart_item(item_id):
    try:
        return {"item": CartService.remove_item(current_customer().id, item_id)}
    except LookupError as exc:
        return {"error": "cart_item_not_found", "detail": str(exc)}, 404


@api_bp.delete("/me/cart")
@customer_required
def clear_my_cart():
    return {"item": CartService.clear_cart(current_customer().id)}

@api_bp.get("/me/cart")
@customer_required
def my_cart():
    from .cart import CartService
    try:
        return {"item": CartService.get_cart(
            current_customer().id,
            request.args.get("currency_id", type=int),
        )}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_read_failed", "detail": str(exc)}, 400


@api_bp.post("/me/payment-proofs/upload")
@customer_required
def upload_my_payment_proof():
    from ...models import PaymentTransaction
    order_id = request.form.get("order_id", type=int)
    order = db.session.get(Order, order_id) if order_id else None
    if order is None or order.customer_id != current_customer().id:
        return {"error": "not_found"}, 404
    files = request.files.getlist("files")
    if not files:
        return {"error": "file_required", "detail": "اختر صورة أو ملف إثبات الدفع."}, 400
    from ..catalog.services import MediaService
    try:
        assets = MediaService.save_generic_files(files[:3], f"payments/{order.id}")
        tx = (
            PaymentTransaction.query
            .filter_by(order_id=order.id, status="pending")
            .order_by(PaymentTransaction.id.desc())
            .first()
        )
        if tx is None:
            raise ValueError("اختر طريقة الدفع أولًا قبل رفع إثبات الدفع.")
        from ..support.services import SupportService
        conversation = (
            Conversation.query
            .filter_by(customer_id=current_customer().id, order_id=order.id)
            .order_by(Conversation.id.desc())
            .first()
        )
        if conversation is None:
            conversation = SupportService.create_conversation(
                current_customer().id,
                "order_support",
                order.id,
                "الطلب " + order.order_no,
            )
            conversation = db.session.get(Conversation, conversation["id"])

        rows = []
        proof_assets = []
        for asset in assets:
            proof = PaymentProof(
                order_id=order.id,
                transaction_id=tx.id,
                asset_id=asset["id"],
                submitted_by=current_customer().id,
                status="pending",
            )
            db.session.add(proof)
            proof_assets.append((proof, asset))
            rows.append({
                "id": None,
                "order_id": order.id,
                "asset_id": asset["id"],
                "url": asset["url"],
                "status": "pending",
            })

        order.payment_status = "pending_proof"
        db.session.flush()

        # A proof uploaded directly from the order page is also recorded as a
        # normal payment-proof message in the order conversation, so the
        # customer and support team see the same proof in both places.
        message = SupportService.send_message(
            conversation.id,
            "customer",
            current_customer().id,
            "تم رفع إثبات الدفع من صفحة الطلب.",
            "payment_proof",
            [
                {
                    "id": asset["id"],
                    "mime_type": asset["mime_type"],
                    "sort_order": idx,
                }
                for idx, (_, asset) in enumerate(proof_assets)
            ],
        )
        for row, (proof, _) in zip(rows, proof_assets):
            row["id"] = proof.id
            row["message_id"] = message["id"]
        db.session.commit()
        return {"items": rows}
    except (ValueError, LookupError) as exc:
        db.session.rollback()
        return {"error": "payment_proof_upload_failed", "detail": str(exc)}, 400


@api_bp.post("/me/payment-proofs")
@customer_required
def my_payment_proof():
    payload = request.get_json(silent=True) or {}
    order = db.session.get(Order, int(payload["order_id"]))
    if order is None or order.customer_id != current_customer().id:
        return {"error": "not_found"}, 404
    from .payment_shipping import PaymentShippingService
    payload["submitted_by"] = current_customer().id
    try:
        return {"item": PaymentShippingService.attach_payment_proof(payload)}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "payment_proof_failed", "detail": str(exc)}, 400
