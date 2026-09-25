from flask import request

from . import api_bp
from ...security import admin_api_required
from ..customer.security import customer_required, current_customer
from .services import CommerceService
from ...extensions import db
from ...models import Order


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
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_update_failed", "detail": str(exc)}, 400
    return {"item": item}, 201


from .payment_shipping import PaymentShippingService


@api_bp.get("/payment-methods")
def payment_methods():
    from ...models import PaymentMethod
    rows = PaymentMethod.query.filter_by(is_active=True).order_by(PaymentMethod.id).all()
    return {"items": [{"id": x.id, "name": x.name, "code": x.code, "provider": x.provider, "supports_proof": x.supports_proof} for x in rows]}


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
def payment_proof():
    try:
        return {"item": PaymentShippingService.attach_payment_proof(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "payment_proof_failed", "detail": str(exc)}, 400


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
def get_cart(customer_id):
    try:
        return {"item": CartService.get_cart(customer_id, request.args.get("currency_id", type=int))}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_read_failed", "detail": str(exc)}, 400


@api_bp.delete("/cart/<int:customer_id>/items/<int:item_id>")
def remove_cart_item(customer_id, item_id):
    try:
        return {"item": CartService.remove_item(customer_id, item_id)}
    except LookupError as exc:
        return {"error": "cart_item_not_found", "detail": str(exc)}, 404


@api_bp.delete("/cart/<int:customer_id>")
def clear_cart(customer_id):
    return {"item": CartService.clear_cart(customer_id)}


@api_bp.get("/me/orders")
@customer_required
def my_orders():
    from ...models import Order
    rows = Order.query.filter_by(customer_id=current_customer().id).order_by(Order.id.desc()).limit(200).all()
    return {"items": [CommerceService.serialize_order(x) for x in rows]}


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


@api_bp.post("/me/cart/items")
@customer_required
def my_cart_item():
    payload = request.get_json(silent=True) or {}
    try:
        item = CommerceService.add_to_cart(
            current_customer().id,
            int(payload["variant_id"]),
            int(payload.get("qty", 1)),
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "cart_update_failed", "detail": str(exc)}, 400
    return {"item": item}, 201


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
