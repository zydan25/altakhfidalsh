from app.extensions import db
from app.models import AppSetting, Customer, CustomerNotification, Conversation, Notification
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



def test_fcm_supports_action_buttons_without_breaking_legacy_clients(app):
    from app.services.fcm import FCMService

    payload = {
        "notification_id": 91,
        "show_action_button": True,
        "action_label": "عرض التفاصيل",
        "action_color": "#7F56D9",
        "accent_color": "#16A085",
        "image_url": "/media/notifications/example.jpg",
        "target": "home",
    }
    with app.app_context():
        action_message = FCMService._message(
            "عنوان تجريبي",
            "وصف تجريبي",
            payload,
            "test-token",
            local_actions=True,
        )
        legacy_message = FCMService._message(
            "عنوان تجريبي",
            "وصف تجريبي",
            payload,
            "test-token",
            local_actions=False,
        )

    assert action_message.notification is None
    assert action_message.android.notification is None
    assert action_message.data["title"] == "عنوان تجريبي"
    assert action_message.data["body"] == "وصف تجريبي"
    assert action_message.data["show_action_button"] == "true"
    assert action_message.data["action_label"] == "عرض التفاصيل"
    assert action_message.data["action_color"] == "#7F56D9"
    assert action_message.data["image_url"].startswith("https://")
    # Existing APKs keep working until they upgrade and re-register.
    assert legacy_message.notification is not None
    assert legacy_message.notification.title == "عنوان تجريبي"
    assert legacy_message.android.notification is not None


def test_disabled_automatic_product_notifications_are_skipped_but_manual_sends_work(app):
    with app.app_context():
        customer = Customer(phone_normalized="967700000003", status="active")
        db.session.add(customer)
        db.session.add(AppSetting(
            group_code="notifications",
            key="new_product_enabled",
            value="false",
            value_type="boolean",
        ))
        db.session.commit()

        result = NotificationService.broadcast(
            "منتج جديد",
            "وصف المنتج",
            {
                "type": "new_product",
                "target": "product",
                "product_id": 7,
            },
        )
        assert result["skipped"] is True
        assert result["count"] == 0
        assert Notification.query.filter_by(customer_id=customer.id).count() == 0

        manual = NotificationService.create(
            customer.id,
            "new_product",
            "إشعار يدوي",
            "هذا الإشعار أرسله المسؤول يدويًا.",
            {
                "type": "new_product",
                "target": "product",
                "product_id": 7,
                "_manual_send": True,
            },
        )
        assert manual is not None
        assert manual["title"] == "إشعار يدوي"
        assert "_manual_send" not in manual["data"]
        assert Notification.query.filter_by(customer_id=customer.id).count() == 1


def test_broadcast_keeps_one_editable_record_per_recipient(app):
    with app.app_context():
        customers = [
            Customer(phone_normalized="967700000004", status="active"),
            Customer(phone_normalized="967700000005", status="active"),
        ]
        db.session.add_all(customers)
        db.session.commit()

        result = NotificationService.broadcast(
            "إعلان تجريبي",
            "وصف تجريبي",
            {"type": "announcement", "screen_type": "home", "target": "home"},
        )
        assert result["count"] == 2
        rows = Notification.query.filter(
            Notification.customer_id.in_([x.id for x in customers]),
            Notification.title == "إعلان تجريبي",
        ).all()
        assert len(rows) == 2
        assert len({row.customer_id for row in rows}) == 2
        assert all(row.status == "sent" for row in rows)
