from flask import request

from . import api_bp
from ...extensions import db
from ...models import CustomerNotification, Notification


@api_bp.get("/notifications/<int:customer_id>")
def notifications(customer_id):
    rows = CustomerNotification.query.filter_by(customer_id=customer_id).join(Notification).order_by(CustomerNotification.id.desc()).limit(100).all()
    return {"items": [
        {
            "id": x.notification_id,
            "type": x.notification.type,
            "title": x.notification.title if hasattr(x, "notification") else None,
            "body": x.notification.body if hasattr(x, "notification") else None,
            "data": x.notification.data if hasattr(x, "notification") else {},
            "read_at": x.read_at.isoformat() if x.read_at else None,
        }
        for x in rows
    ]}


@api_bp.post("/notifications/<int:customer_id>/<int:notification_id>/read")
def mark_read(customer_id, notification_id):
    row = CustomerNotification.query.filter_by(customer_id=customer_id, notification_id=notification_id).first()
    if row is None:
        notification = db.session.get(Notification, notification_id)
        if notification is None or notification.customer_id != customer_id:
            return {"error": "not_found"}, 404
        row = CustomerNotification(customer_id=customer_id, notification_id=notification_id)
        db.session.add(row)
    row.read_at = db.func.now()
    db.session.commit()
    return {"ok": True, "read": True}
