from flask import Blueprint, current_app, request

from .extensions import db
from .models import Conversation, Customer, Message
from .services.phone import normalize_phone

webhooks_bp = Blueprint("webhooks", __name__)


def _check_session(payload):
    configured = current_app.config.get("WHATSAPP_SESSION", "basheer")
    session = payload.get("session") or payload.get("botId")
    return not session or session == configured


@webhooks_bp.post("/webhook/whatsapp")
def whatsapp_message():
    payload = request.get_json(silent=True) or {}
    if not _check_session(payload):
        return {"ok": True, "ignored": True}
    sender = str(payload.get("from") or "").split("@", 1)[0]
    if not sender:
        return {"ok": True}
    phone = normalize_phone(sender)
    customer = Customer.query.filter_by(phone_normalized=phone).first()
    if customer is None:
        return {"ok": True, "ignored": True, "reason": "unknown_customer"}
    conversation = Conversation.query.filter_by(
        customer_id=customer.id,
        status="open",
    ).order_by(Conversation.id.desc()).first()
    if conversation is None:
        conversation = Conversation(
            customer_id=customer.id,
            type="whatsapp",
            subject="WhatsApp",
            status="open",
        )
        db.session.add(conversation)
        db.session.flush()
    message = Message(
        conversation_id=conversation.id,
        sender_type="customer",
        sender_id=customer.id,
        message_type=payload.get("type") or "text",
        body=payload.get("body") or "",
    )
    db.session.add(message)
    conversation.last_message_at = db.func.now()
    db.session.commit()
    return {"ok": True}


@webhooks_bp.post("/webhook/session-status")
def whatsapp_session_status():
    payload = request.get_json(silent=True) or {}
    if not _check_session(payload):
        return {"ok": True, "ignored": True}
    current_app.logger.info("WhatsApp session status: %s", payload)
    return {"ok": True}


@webhooks_bp.post("/webhook/qr")
def whatsapp_qr():
    payload = request.get_json(silent=True) or {}
    if not _check_session(payload):
        return {"ok": True, "ignored": True}
    current_app.logger.info("WhatsApp QR event received for session=%s", payload.get("session"))
    return {"ok": True}
