from flask import request

from . import api_bp
from .services import CommerceService
from ...extensions import db
from ...models import Order


@api_bp.get("/orders")
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
def order(order_id):
    item = db.session.get(Order, order_id)
    if item is None:
        return {"error": "not_found"}, 404
    return {"item": CommerceService.serialize_order(item)}


@api_bp.post("/orders")
def create_order():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CommerceService.create_order(payload)}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "order_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/orders/<int:order_id>/status")
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
