from app.extensions import db
from app.models import Customer, CustomerNotification, Conversation, Notification
from app.modules.support.services import SupportService
from app.services.notifications import NotificationService


def test_admin_message_creates_customer_notification(app):
    with app.app_context():
        customer = Customer(phone_normalized="967700000001", status="active")
        db.session.add(customer)
        db.session.flush()

        conversation = Conversation(
            customer_id=customer.id,
            type="customer_service",
            subject="خدمة العملاء",
            status="open",
        )
        db.session.add(conversation)
        db.session.commit()

        message = SupportService.send_message(
            conversation.id,
            "admin",
            9,
            "مرحبًا، تم تحديث طلبك.",
            "text",
        )

        notification = Notification.query.filter_by(
            customer_id=customer.id,
            type="message",
        ).order_by(Notification.id.desc()).first()
        assert notification is not None
        assert notification.title == "رسالة جديدة من الإدارة"
        assert notification.body == "مرحبًا، تم تحديث طلبك."
        assert notification.data["conversation_id"] == conversation.id
        assert notification.data["target"] == "conversation"
        assert CustomerNotification.query.filter_by(
            customer_id=customer.id,
            notification_id=notification.id,
        ).first() is not None
        assert message["sender_type"] == "admin"


def test_order_status_notification_contains_navigation_data(app):
    with app.app_context():
        customer = Customer(phone_normalized="967700000002", status="active")
        db.session.add(customer)
        db.session.flush()

        class OrderRef:
            customer_id = customer.id
            id = 41
            order_no = "ORD-41"
            status = "processing"

        notification = NotificationService.order_status_changed(
            OrderRef(),
            "بدأ المتجر تجهيز طلبك.",
            "processing",
        )
        assert notification["type"] == "order_status"
        assert notification["data"]["order_id"] == 41
        assert notification["data"]["order_no"] == "ORD-41"
        assert notification["data"]["status"] == "processing"
        assert notification["data"]["target"] == "order"

        row = Notification.query.get(notification["id"])
        assert row is not None
        assert CustomerNotification.query.filter_by(
            customer_id=customer.id,
            notification_id=row.id,
        ).first() is not None

def test_fcm_reserved_data_key_is_namespaced():
    from app.services.fcm import FCMService

    payload = FCMService._string_data({
        "message_type": "text",
        "target": "conversation",
        "conversation_id": 42,
    })

    assert "message_type" not in payload
    assert payload["data_message_type"] == "text"
    assert payload["target"] == "conversation"
    assert payload["conversation_id"] == "42"
