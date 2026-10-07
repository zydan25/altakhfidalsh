from app.extensions import db
from app.models import Customer
from app.modules.customer.services import CustomerService


def test_customer_receives_invite_code_on_direct_creation(app):
    with app.app_context():
        customer = Customer(
            phone_normalized="967700001101",
            name="المدعو الأول",
            status="active",
        )
        db.session.add(customer)
        db.session.commit()

        assert customer.invite_code
        assert len(customer.invite_code) == 8


def test_referral_code_can_be_applied_once_and_is_reported(app):
    with app.app_context():
        inviter = Customer(
            phone_normalized="967700001102",
            name="صاحب الدعوة",
            status="active",
        )
        invited = Customer(
            phone_normalized="967700001103",
            name="العضو الجديد",
            status="active",
        )
        db.session.add_all([inviter, invited])
        db.session.commit()

        result = CustomerService.apply_referral(
            invited.id,
            inviter.invite_code,
        )
        assert result["applied"] is True
        assert invited.referred_by_customer_id == inviter.id

        overview = CustomerService.referral_overview(inviter.id)
        assert overview["invite_code"] == inviter.invite_code
        assert overview["invited_count"] == 1
        assert overview["invited_users"][0]["id"] == invited.id

        repeat = CustomerService.apply_referral(
            invited.id,
            inviter.invite_code,
        )
        assert repeat["already_referred"] is True
