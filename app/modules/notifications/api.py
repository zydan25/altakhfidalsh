from flask import current_app, request

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


@api_bp.post("/webhook/whatsapp")
def whatsapp_webhook():
    payload = request.get_json(silent=True) or {}
    from ...models import Customer, Conversation, Message
    from ...extensions import db
    bot_id = payload.get("botId") or payload.get("session")
    if bot_id and bot_id != current_app.config.get("WHATSAPP_SESSION", "basheer"):
        return {"ok": True, "ignored": True}
    sender = str(payload.get("from") or "").split("@", 1)[0]
    body = payload.get("body") or ""
    if not sender:
        return {"ok": True}
    from ...services.phone import normalize_phone
    phone = normalize_phone(sender)
    customer = Customer.query.filter_by(phone_normalized=phone).first()
    if customer is None:
        return {"ok": True, "ignored": True, "reason": "unknown_customer"}
    conversation = Conversation.query.filter_by(customer_id=customer.id, status="open").order_by(Conversation.id.desc()).first()
    if conversation is None:
        conversation = Conversation(customer_id=customer.id, type="whatsapp", subject="WhatsApp", status="open")
        db.session.add(conversation)
        db.session.flush()
    db.session.add(Message(
        conversation_id=conversation.id,
        sender_type="customer",
        sender_id=customer.id,
        message_type=payload.get("type") or "text",
        body=body,
    ))
    conversation.last_message_at = db.func.now()
    db.session.commit()
    return {"ok": True}


@api_bp.post("/webhook/session-status")
def whatsapp_session_status_webhook():
    payload = request.get_json(silent=True) or {}
    return {"ok": True, "session": payload.get("session"), "status": payload.get("status")}


@api_bp.post("/webhook/qr")
def whatsapp_qr_webhook():
    payload = request.get_json(silent=True) or {}
    return {"ok": True, "session": payload.get("session")}
