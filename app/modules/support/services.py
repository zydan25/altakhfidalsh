from ...extensions import db
from ...models import Conversation, Message, MessageAttachment, MediaAsset


class SupportService:
    @staticmethod
    def create_conversation(customer_id, conversation_type, order_id=None, subject=None):
        conversation = Conversation(
            customer_id=customer_id,
            order_id=order_id,
            type=conversation_type,
            subject=subject,
            status="open",
        )
        db.session.add(conversation)
        db.session.commit()
        return {
            "id": conversation.id,
            "customer_id": conversation.customer_id,
            "order_id": conversation.order_id,
            "type": conversation.type,
            "subject": conversation.subject,
            "status": conversation.status,
        }

    @staticmethod
    def send_message(conversation_id, sender_type, sender_id, body, message_type="text"):
        conversation = db.session.get(Conversation, conversation_id)
        if conversation is None:
            raise LookupError("conversation not found")
        if not body and message_type == "text":
            raise ValueError("message body is required")
        message = Message(
            conversation_id=conversation_id,
            sender_type=sender_type,
            sender_id=int(sender_id),
            message_type=message_type,
            body=body,
        )
        db.session.add(message)
        db.session.flush()
        conversation.last_message_at = db.func.now()
        db.session.commit()
        return {
            "id": message.id,
            "conversation_id": message.conversation_id,
            "sender_type": message.sender_type,
            "sender_id": message.sender_id,
            "message_type": message.message_type,
            "body": message.body,
            "created_at": message.created_at.isoformat(),
        }
