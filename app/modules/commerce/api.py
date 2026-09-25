from ...extensions import db
from flask import request

from . import api_bp
from ...models import Order, OrderItem


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
        "items": [
            {
                "id": x.id,
                "order_no": x.order_no,
                "customer_id": x.customer_id,
                "currency_id": x.currency_id,
                "total": str(x.total),
                "status": x.status,
                "payment_status": x.payment_status,
                "shipping_status": x.shipping_status,
            }
            for x in pagination.items
        ],
        "pagination": {"page": pagination.page, "per_page": pagination.per_page, "pages": pagination.pages, "total": pagination.total},
    }


@api_bp.get("/orders/<int:order_id>")
def order(order_id):
    item = db.session.get(Order, order_id)
    if item is None:
        return {"error": "not_found"}, 404
    return {
        "id": item.id,
        "order_no": item.order_no,
        "customer_id": item.customer_id,
        "address_snapshot": item.address_snapshot,
        "currency_id": item.currency_id,
        "pricing_group_id": item.pricing_group_id,
        "fx_rate": str(item.fx_rate),
        "subtotal": str(item.subtotal),
        "discount": str(item.discount),
        "shipping": str(item.shipping),
        "total": str(item.total),
        "status": item.status,
    }
