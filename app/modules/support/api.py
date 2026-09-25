from flask import request

from . import api_bp
from ...models import Conversation, Message


@api_bp.get("/conversations")
def conversations():
    rows = Conversation.query.order_by(Conversation.last_message_at.desc(), Conversation.id.desc()).limit(100).all()
    return {
        "items": [
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
        ]
    }


@api_bp.get("/conversations/<int:conversation_id>/messages")
def messages(conversation_id):
    rows = Message.query.filter_by(conversation_id=conversation_id).order_by(Message.created_at, Message.id).all()
    return {"items": [{"id": x.id, "sender_type": x.sender_type, "sender_id": x.sender_id, "message_type": x.message_type, "body": x.body, "created_at": x.created_at.isoformat()} for x in rows]}
