from ...extensions import db
from ...models import Conversation, Message, MessageAttachment


class SupportService:
    @staticmethod
    def create_conversation(customer_id, conversation_type, order_id=None, subject=None):
        conversation_type = (conversation_type or "customer_service").strip()[:40]

        # Keep one ongoing support thread per customer. Order-specific
        # conversations remain separate so each order can have its own context.
        if conversation_type == "customer_service" and order_id is None:
            conversation = (
                Conversation.query
                .filter(
                    Conversation.customer_id == customer_id,
                    Conversation.type == "customer_service",
                    Conversation.order_id.is_(None),
                    Conversation.status.in_(("open", "pending")),
                )
                .order_by(Conversation.last_message_at.desc(), Conversation.id.desc())
                .first()
            )
            if conversation is not None:
                return {
                    "id": conversation.id,
                    "customer_id": conversation.customer_id,
                    "order_id": conversation.order_id,
                    "type": conversation.type,
                    "subject": conversation.subject or "محادثة الدعم",
                    "status": conversation.status,
                }

        conversation = Conversation(
            customer_id=customer_id,
            order_id=int(order_id) if order_id not in (None, "") else None,
            type=conversation_type,
            subject=(subject or "").strip()[:200] or (
                "محادثة الدعم" if conversation_type == "customer_service" else "استفسار عن الطلب"
            ),
            status="open",
            last_message_at=db.func.now(),
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
    def send_message(conversation_id, sender_type, sender_id, body, message_type="text", attachments=None):
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
        attachment_rows = []
        for asset in attachments or []:
            attachment_rows.append(MessageAttachment(
                message_id=message.id,
                asset_id=asset["id"],
                mime_type=asset["mime_type"],
                sort_order=asset.get("sort_order", 0),
            ))
        db.session.add_all(attachment_rows)
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


    @staticmethod
    def send_message_with_files(conversation_id, sender_type, sender_id, body, files, payment_proof=False):
        from ..catalog.services import MediaService
        from ...models import Order, PaymentProof, PaymentTransaction
        conversation = db.session.get(Conversation, conversation_id)
        if conversation is None:
            raise LookupError("conversation not found")
        if payment_proof and conversation.order_id is None:
            raise ValueError("إثبات الدفع يجب أن يكون داخل محادثة مرتبطة بطلب.")
        assets = MediaService.save_generic_files(files, f"conversations/{conversation_id}")
        message = SupportService.send_message(
            conversation_id,
            sender_type,
            sender_id,
            body,
            "payment_proof" if payment_proof else "attachment",
            assets,
        )
        if payment_proof:
            order = db.session.get(Order, conversation.order_id)
            tx = (
                PaymentTransaction.query
                .filter_by(order_id=order.id, status="pending")
                .order_by(PaymentTransaction.id.desc())
                .first()
            )
            if tx is None:
                raise ValueError("اختر طريقة الدفع للطلب أولًا.")
            proof = PaymentProof(
                order_id=order.id,
                transaction_id=tx.id,
                asset_id=assets[0]["id"],
                submitted_by=sender_id,
                status="pending",
            )
            db.session.add(proof)
            order.payment_status = "pending_proof"
            db.session.commit()
            message["payment_proof_id"] = proof.id
            message["payment_proof_status"] = proof.status
        return message
