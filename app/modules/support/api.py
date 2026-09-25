from flask import request

from . import api_bp
from .services import SupportService
from ...extensions import db
from ...models import Conversation, Message


@api_bp.post("/conversations")
@customer_required
def create_conversation():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": SupportService.create_conversation(
            current_customer().id,
            str(payload.get("type", "customer_service")),
            payload.get("order_id"),
            payload.get("subject"),
        )}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "conversation_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/conversations")
@customer_required
def conversations():
    customer_id = current_customer().id
    query = Conversation.query.filter(Conversation.customer_id == customer_id)
    rows = query.order_by(Conversation.last_message_at.desc(), Conversation.id.desc()).limit(100).all()
    return {"items": [
        {
            "id": x.id,
            "customer_id": x.customer_id,
            "order_id": x.order_id,
            "type": x.type,
            "subject": x.subject,
            "status": x.status,
            "last_message_at": x.last_message_at.isoformat() if x.last_message_at else None,
        }
        for x in rows
    ]}


@api_bp.get("/conversations/<int:conversation_id>/messages")
@customer_required
def messages(conversation_id):
    conversation = db.session.get(Conversation, conversation_id)
    if conversation is None or conversation.customer_id != current_customer().id:
        return {"error": "not_found"}, 404
    rows = Message.query.filter_by(conversation_id=conversation_id).order_by(Message.created_at, Message.id).all()
    return {"items": [
        {
            "id": x.id,
            "sender_type": x.sender_type,
            "sender_id": x.sender_id,
            "message_type": x.message_type,
            "body": x.body,
            "created_at": x.created_at.isoformat(),
        }
        for x in rows
    ]}


@api_bp.post("/conversations/<int:conversation_id>/messages")
@customer_required
def send_message(conversation_id):
    payload = request.get_json(silent=True) or {}
    conversation = db.session.get(Conversation, conversation_id)
    if conversation is None or conversation.customer_id != current_customer().id:
        return {"error": "not_found"}, 404
    try:
        return {"item": SupportService.send_message(
            conversation_id,
            "customer",
            current_customer().id,
            payload.get("body"),
            str(payload.get("message_type", "text")),
        )}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "message_send_failed", "detail": str(exc)}, 400


@api_bp.post("/conversations/<int:conversation_id>/attachments")
@customer_required
def send_attachments(conversation_id):
    sender_type = request.form.get("sender_type", "customer")
    conversation = db.session.get(Conversation, conversation_id)
    if conversation is None or conversation.customer_id != current_customer().id:
        return {"error": "not_found"}, 404
    try:
        return {"item": SupportService.send_message_with_files(
            conversation_id,
            "customer",
            current_customer().id,
            request.form.get("body"),
            request.files.getlist("files"),
        )}, 201
    except (ValueError, LookupError) as exc:
        return {"error": "attachment_send_failed", "detail": str(exc)}, 400
