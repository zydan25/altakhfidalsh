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


@api_bp.get("/whatsapp/console")
@__import__("app.security", fromlist=["admin_api_required"]).admin_api_required("system.manage")
def whatsapp_console():
    from ...services.whatsapp import WhatsAppService
    result = {}
    for key, loader in (
        ("status", WhatsAppService.status),
        ("qr", WhatsAppService.qr),
        ("messages", WhatsAppService.messages),
        ("errors", WhatsAppService.errors),
        ("notifications", WhatsAppService.notifications),
    ):
        try:
            result[key] = loader()
        except Exception as exc:
            result[key] = {"success": False, "error": str(exc)}
    return result


@api_bp.post("/whatsapp/<action>")
@__import__("app.security", fromlist=["admin_api_required"]).admin_api_required("system.manage")
def whatsapp_action(action):
    from ...services.whatsapp import WhatsAppService
    actions = {
        "connect": WhatsAppService.connect,
        "disconnect": WhatsAppService.disconnect,
        "logout": WhatsAppService.logout,
    }
    fn = actions.get(action)
    if fn is None:
        return {"error": "unsupported_action"}, 400
    try:
        return {"item": fn()}
    except Exception as exc:
        return {"error": "whatsapp_request_failed", "detail": str(exc)}, 502


@api_bp.post("/whatsapp/send")
@__import__("app.security", fromlist=["admin_api_required"]).admin_api_required("system.manage")
def whatsapp_send():
    from ...services.whatsapp import WhatsAppService
    phone = (request.form.get("phoneNumber") or "").strip()
    message = request.form.get("message") or ""
    media = request.files.get("media")
    if not phone:
        return {"error": "phoneNumber_required"}, 400
    try:
        result = WhatsAppService.send_media(phone, message, media) if media and media.filename else WhatsAppService.send_text(phone, message)
        return {"item": result}
    except Exception as exc:
        return {"error": "whatsapp_send_failed", "detail": str(exc)}, 502


@api_bp.post("/whatsapp/api-url")
@__import__("app.security", fromlist=["admin_api_required"]).admin_api_required("system.manage")
def whatsapp_api_url():
    from ...services.whatsapp import WhatsAppService
    payload = request.get_json(silent=True) or {}
    url = str(payload.get("apiBaseUrl", "")).strip()
    if not url:
        return {"error": "apiBaseUrl_required"}, 400
    try:
        return {"item": WhatsAppService.api_url(url)}
    except Exception as exc:
        return {"error": "whatsapp_request_failed", "detail": str(exc)}, 502
