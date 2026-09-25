from decimal import Decimal
from datetime import datetime, timezone

from ...extensions import db
from ...models import Coupon, CouponRedemption, GiftCampaign, GiftIssuance, Wallet, WalletTransaction


class PromotionService:
    @staticmethod
    def redeem_coupon(code, customer_id, order_id, order_subtotal):
        coupon = Coupon.query.filter_by(code=code, is_active=True).first()
        if coupon is None:
            raise LookupError("coupon not found")
        now = datetime.now(timezone.utc)
        if coupon.starts_at and coupon.starts_at > now or coupon.ends_at and coupon.ends_at < now:
            raise ValueError("coupon is outside its validity window")
        used = CouponRedemption.query.filter_by(coupon_id=coupon.id).count()
        if coupon.usage_limit is not None and used >= coupon.usage_limit:
            raise ValueError("coupon usage limit reached")
        previous = CouponRedemption.query.filter_by(coupon_id=coupon.id, customer_id=customer_id).first()
        if previous:
            raise ValueError("coupon already redeemed by customer")
        subtotal = Decimal(str(order_subtotal))
        if coupon.min_order is not None and subtotal < Decimal(coupon.min_order):
            raise ValueError("minimum order requirement not met")

        if coupon.type == "percent":
            discount = subtotal * Decimal(coupon.value) / Decimal("100")
        else:
            discount = Decimal(coupon.value)
        if coupon.max_discount is not None:
            discount = min(discount, Decimal(coupon.max_discount))
        discount = min(discount, subtotal)

        db.session.add(CouponRedemption(
            coupon_id=coupon.id,
            customer_id=customer_id,
            order_id=order_id,
            discount_amount=discount,
        ))
        db.session.commit()
        return {"coupon_id": coupon.id, "code": coupon.code, "discount_amount": str(discount)}

    @staticmethod
    def issue_gift(campaign_id, customer_id):
        campaign = db.session.get(GiftCampaign, campaign_id)
        if campaign is None or not campaign.is_active:
            raise LookupError("gift campaign not found")
        issuance = GiftIssuance(
            campaign_id=campaign.id,
            customer_id=customer_id,
            gift_code="GIFT-" + __import__("secrets").token_hex(6).upper(),
            amount=campaign.value,
            expires_at=campaign.expires_at,
        )
        db.session.add(issuance)
        db.session.commit()
        return {"id": issuance.id, "gift_code": issuance.gift_code, "amount": str(issuance.amount) if issuance.amount is not None else None}

    @staticmethod
    def adjust_wallet(customer_id, currency_id, amount, transaction_type, reference_type=None, reference_id=None):
        amount = Decimal(str(amount))
        wallet = Wallet.query.filter_by(customer_id=customer_id, currency_id=currency_id).first()
        if wallet is None:
            wallet = Wallet(customer_id=customer_id, currency_id=currency_id, balance=Decimal("0"))
            db.session.add(wallet)
            db.session.flush()
        new_balance = Decimal(wallet.balance) + amount
        if new_balance < 0:
            raise ValueError("wallet balance cannot be negative")
        wallet.balance = new_balance
        tx = WalletTransaction(
            wallet_id=wallet.id,
            type=transaction_type,
            amount=amount,
            currency_id=currency_id,
            reference_type=reference_type,
            reference_id=reference_id,
            balance_after=new_balance,
        )
        db.session.add(tx)
        db.session.commit()
        return {"wallet_id": wallet.id, "balance": str(wallet.balance), "transaction_id": tx.id}
