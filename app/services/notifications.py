from datetime import datetime, timezone

from ...extensions import db
from ...models import CustomerNotification, Notification


class NotificationService:
    """Create durable in-app customer notifications from business events."""

    @staticmethod
    def create(customer_id, notification_type, title, body, data=None):
        customer_id = int(customer_id)
        row = Notification(
            customer_id=customer_id,
            type=str(notification_type or "general")[:60],
            title=str(title or "إشعار")[:240],
            body=str(body or "")[:10000],
            data=dict(data or {}),
            status="sent",
            sent_at=datetime.now(timezone.utc),
        )
        db.session.add(row)
        db.session.flush()
        db.session.add(
            CustomerNotification(
                customer_id=customer_id,
                notification_id=row.id,
            )
        )
        db.session.commit()
        return {
            "id": row.id,
            "type": row.type,
            "title": row.title,
            "body": row.body,
            "data": row.data,
            "read_at": None,
        }

    @staticmethod
    def order_status_changed(order, body, status=None):
        status = status or order.status
        return NotificationService.create(
            order.customer_id,
            "order_status",
            "تحديث طلبك",
            body,
            {
                "order_id": order.id,
                "order_no": order.order_no,
                "status": status,
                "target": "order",
            },
        )

    @staticmethod
    def message_received(conversation, message_body, message_type="text"):
        title = "رسالة جديدة من الإدارة"
        prefix = "رسالة جديدة"
        if conversation.order_id:
            title = "رسالة جديدة بخصوص طلبك"
            prefix = "طلب " + str(conversation.order_id)

        body = str(message_body or "").strip()
        if message_type != "text" and not body:
            body = "لديك مرفق جديد من الإدارة."
        elif not body:
            body = "لديك رسالة جديدة من الإدارة."
        elif len(body) > 240:
            body = body[:237] + "..."

        return NotificationService.create(
            conversation.customer_id,
            "message",
            title,
            body,
            {
                "conversation_id": conversation.id,
                "order_id": conversation.order_id,
                "message_type": message_type,
                "target": "conversation",
                "preview": prefix,
            },
        )

    @staticmethod
    def payment_updated(order, title, body, payment_status=None):
        return NotificationService.create(
            order.customer_id,
            "payment",
            title,
            body,
            {
                "order_id": order.id,
                "order_no": order.order_no,
                "payment_status": payment_status or order.payment_status,
                "target": "order",
            },
        )

    @staticmethod
    def shipping_updated(order, body, shipping_status=None):
        return NotificationService.create(
            order.customer_id,
            "shipping",
            "تحديث التوصيل",
            body,
            {
                "order_id": order.id,
                "order_no": order.order_no,
                "shipping_status": shipping_status or order.shipping_status,
                "target": "order",
            },
        )
