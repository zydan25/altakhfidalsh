import json
import logging
from datetime import datetime, timezone

from sqlalchemy import or_, text

from ..extensions import db
from ..models import Customer, CustomerNotification, CustomerPreference, Notification
from .fcm import FCMService

logger = logging.getLogger(__name__)


class NotificationService:
    """Create durable in-app and real-time customer notifications."""

    @staticmethod
    def _emit(customer_id, notification_id, notification=None):
        payload_data = {
            "customer_id": int(customer_id),
            "notification_id": int(notification_id),
        }
        if notification is not None:
            payload_data.update({
                "type": notification.type,
                "title": notification.title,
                "body": notification.body,
                "data": notification.data or {},
                "sent_at": notification.sent_at.isoformat() if notification.sent_at else None,
            })
        payload = json.dumps(
            payload_data,
            separators=(",", ":"),
        )
        try:
            if db.session.bind and db.session.bind.dialect.name == "postgresql":
                db.session.execute(
                    text("SELECT pg_notify(:channel, :payload)"),
                    {
                        "channel": "customer_notifications",
                        "payload": payload,
                    },
                )
        except Exception:
            # WebSocket delivery is best-effort. The durable row remains the
            # source of truth and will be available through the notifications API.
            pass

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
        NotificationService._emit(customer_id, row.id, row)
        db.session.commit()
        try:
            result = FCMService.send_to_customer(customer_id, row.title, row.body, {
                **dict(row.data or {}),
                "notification_id": row.id,
                "type": row.type,
            })
            logger.info(
                "FCM customer notification id=%s customer_id=%s result=%s",
                row.id, customer_id, result,
            )
        except Exception:
            logger.exception(
                "FCM customer notification failed id=%s customer_id=%s",
                row.id, customer_id,
            )
        return {
            "id": row.id,
            "type": row.type,
            "title": row.title,
            "body": row.body,
            "data": row.data,
            "read_at": None,
        }

    @staticmethod
    def broadcast(title, body, data=None):
        """Send one notification to all active customers with notifications enabled."""
        customer_rows = (
            db.session.query(Customer.id)
            .outerjoin(
                CustomerPreference,
                CustomerPreference.customer_id == Customer.id,
            )
            .filter(
                Customer.status == "active",
                or_(
                    CustomerPreference.customer_id.is_(None),
                    CustomerPreference.notifications_enabled.is_(True),
                ),
            )
            .order_by(Customer.id)
            .all()
        )
        created = []
        for (customer_id,) in customer_rows:
            row = Notification(
                customer_id=int(customer_id),
                type=str((data or {}).get("type") or "announcement")[:60],
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
                    customer_id=int(customer_id),
                    notification_id=row.id,
                )
            )
            created.append((int(customer_id), int(row.id)))
        for customer_id, notification_id in created:
            NotificationService._emit(
                customer_id,
                notification_id,
                db.session.get(Notification, notification_id),
            )
        db.session.commit()
        for customer_id, notification_id in created:
            row = db.session.get(Notification, notification_id)
            if row is None:
                continue
            try:
                result = FCMService.send_to_customer(customer_id, row.title, row.body, {
                    **dict(row.data or {}),
                    "notification_id": row.id,
                    "type": row.type,
                })
                logger.info(
                    "FCM broadcast notification id=%s customer_id=%s result=%s",
                    row.id, customer_id, result,
                )
            except Exception:
                logger.exception(
                    "FCM broadcast notification failed id=%s customer_id=%s",
                    row.id, customer_id,
                )
        return {"count": len(created), "notification_ids": [x[1] for x in created]}

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
