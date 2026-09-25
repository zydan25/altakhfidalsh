from app.extensions import db
from app.models import Admin


def test_admin_phone_otp_flow(client, app, monkeypatch):
    with app.app_context():
        admin = Admin(username="otp-admin", phone="967774952665", is_active=True, status="active")
        db.session.add(admin)
        db.session.commit()

    monkeypatch.setattr(
        "app.services.whatsapp.WhatsAppService.send_text",
        lambda phone, message: {"success": True, "data": {"messageId": "test"}},
    )

    response = client.post(
        "/admin/login",
        data={"action": "request_otp", "phone": "774952665"},
        follow_redirects=False,
    )
    assert response.status_code == 200
    body = response.get_data(as_text=True)
    assert "إعادة إرسال الرمز" in body

    with app.app_context():
        from app.models import OTPRequest
        otp = OTPRequest.query.filter_by(
            phone="967774952665",
            purpose="admin_login",
        ).order_by(OTPRequest.id.desc()).first()
        assert otp is not None
        assert otp.status == "pending"


def test_whatsapp_webhooks_accept_configured_session(client, app):
    with app.app_context():
        from app.models import Customer
        customer = Customer(
            phone_normalized="967700000001",
            name="عميل واتساب",
            status="active",
        )
        db.session.add(customer)
        db.session.commit()

    response = client.post(
        "/webhook/whatsapp",
        json={
            "session": "basheer",
            "botId": "basheer",
            "from": "967700000001@c.us",
            "to": "967700000002@c.us",
            "body": "السلام عليكم",
            "type": "chat",
        },
    )
    assert response.status_code == 200
    assert response.get_json()["ok"] is True

    with app.app_context():
        from app.models import Message
        assert Message.query.count() == 1
