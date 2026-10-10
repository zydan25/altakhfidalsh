from ...extensions import db
from ...models import Conversation, Message, MessageAttachment, Order
from sqlalchemy.exc import IntegrityError


class SupportService:
    @staticmethod
    def create_conversation(customer_id, conversation_type, order_id=None, subject=None):
        conversation_type = (conversation_type or "customer_service").strip()[:40]
        normalized_order_id = (
            int(order_id) if order_id not in (None, "") else None
        )

        if normalized_order_id is not None:
            order = db.session.get(Order, normalized_order_id)
            if order is None:
                raise LookupError("order not found")
            if order.customer_id != int(customer_id):
                raise LookupError("order not found")

            # An order owns exactly one conversation. Reopening the thread
            # must never create a second conversation.
            conversation = (
                Conversation.query
                .filter(Conversation.order_id == normalized_order_id)
                .order_by(Conversation.id.asc())
                .first()
            )
            if conversation is not None:
                if conversation.type != "order_support":
                    conversation.type = "order_support"
                if conversation.subject is None or not conversation.subject.strip():
                    conversation.subject = subject or ("الطلب " + order.order_no)
                conversation.status = "open"
                if conversation.last_message_at is None:
                    conversation.last_message_at = db.func.now()
                db.session.commit()
                return {
                    "id": conversation.id,
                    "customer_id": conversation.customer_id,
                    "order_id": conversation.order_id,
                    "type": conversation.type,
                    "subject": conversation.subject,
                    "status": conversation.status,
                }

            conversation_type = "order_support"
            subject = subject or ("الطلب " + order.order_no)

        # Keep one ongoing support thread per customer for general support.
        if normalized_order_id is None and conversation_type == "customer_service":
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
            order_id=normalized_order_id,
            type=conversation_type,
            subject=(subject or "").strip()[:200] or (
                "محادثة الدعم" if conversation_type == "customer_service" else "استفسار عن الطلب"
            ),
            status="open",
            last_message_at=db.func.now(),
        )
        db.session.add(conversation)
        try:
            db.session.commit()
        except IntegrityError:
            # The unique order-conversation index also protects against two
            # simultaneous "open chat" requests racing each other.
            db.session.rollback()
            if normalized_order_id is not None:
                existing = (
                    Conversation.query
                    .filter(Conversation.order_id == normalized_order_id)
                    .order_by(Conversation.id.asc())
                    .first()
                )
                if existing is not None:
                    existing.type = "order_support"
                    existing.status = "open"
                    db.session.commit()
                    return {
                        "id": existing.id,
                        "customer_id": existing.customer_id,
                        "order_id": existing.order_id,
                        "type": existing.type,
                        "subject": existing.subject or subject or "استفسار عن الطلب",
                        "status": existing.status,
                    }
            raise
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

        # Every administrative/system reply is also a durable customer
        # notification. The message itself remains the source of truth for
        # the conversation; notification creation is intentionally separate.
        if str(sender_type or "").strip().lower() in {"admin", "staff", "employee"}:
            from ...services.notifications import NotificationService
            first_image = next((
                item for item in (attachments or [])
                if str(item.get("mime_type") or "").lower().startswith("image/")
            ), None)
            NotificationService.message_received(
                conversation,
                message.body,
                message.message_type,
                image_url=(first_image or {}).get("url"),
            )

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
