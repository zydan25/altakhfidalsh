from flask import request

from . import api_bp
from ..customer.security import customer_required, current_customer
from ...extensions import db
from ...models import CustomerNotification, Notification


@api_bp.get("/notifications/<int:customer_id>")
@customer_required
def notifications(customer_id):
    if customer_id != current_customer().id:
        return {"error": "forbidden"}, 403
    rows = (
        CustomerNotification.query
        .filter_by(customer_id=customer_id)
        .order_by(CustomerNotification.id.desc())
        .limit(100)
        .all()
    )
    items = []
    for row in rows:
        notification = db.session.get(Notification, row.notification_id)
        if notification is None:
            continue
        items.append({
            "id": notification.id,
            "type": notification.type,
            "title": notification.title,
            "body": notification.body,
            "data": notification.data,
            "read_at": row.read_at.isoformat() if row.read_at else None,
        })
    return {"items": items}


@api_bp.post("/notifications/<int:customer_id>/<int:notification_id>/read")
@customer_required
def mark_read(customer_id, notification_id):
    if customer_id != current_customer().id:
        return {"error": "forbidden"}, 403
    row = CustomerNotification.query.filter_by(
        customer_id=customer_id,
        notification_id=notification_id,
    ).first()
    if row is None:
        notification = db.session.get(Notification, notification_id)
        if notification is None or notification.customer_id != customer_id:
            return {"error": "not_found"}, 404
        row = CustomerNotification(
            customer_id=customer_id,
            notification_id=notification_id,
        )
        db.session.add(row)
    row.read_at = db.func.now()
    db.session.commit()
    return {"ok": True, "read": True}
