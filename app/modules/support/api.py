from flask import request

from . import api_bp
from .services import SupportService
from ...extensions import db
from ...models import Conversation, Message


@api_bp.post("/conversations")
def create_conversation():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": SupportService.create_conversation(
            int(payload["customer_id"]),
            str(payload.get("type", "customer_service")),
            payload.get("order_id"),
            payload.get("subject"),
        )}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "conversation_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/conversations")
def conversations():
    customer_id = request.args.get("customer_id", type=int)
    query = Conversation.query
    if customer_id:
        query = query.filter(Conversation.customer_id == customer_id)
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
def messages(conversation_id):
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
def send_message(conversation_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": SupportService.send_message(
            conversation_id,
            str(payload["sender_type"]),
            int(payload["sender_id"]),
            payload.get("body"),
            str(payload.get("message_type", "text")),
        )}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "message_send_failed", "detail": str(exc)}, 400


@api_bp.post("/conversations/<int:conversation_id>/attachments")
def send_attachments(conversation_id):
    sender_type = request.form.get("sender_type", "customer")
    sender_id = request.form.get("sender_id", type=int)
    if sender_id is None:
        return {"error": "sender_id_required"}, 400
    try:
        return {"item": SupportService.send_message_with_files(
            conversation_id,
            sender_type,
            sender_id,
            request.form.get("body"),
            request.files.getlist("files"),
        )}, 201
    except (ValueError, LookupError) as exc:
        return {"error": "attachment_send_failed", "detail": str(exc)}, 400
