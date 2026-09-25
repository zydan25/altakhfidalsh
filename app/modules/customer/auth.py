import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from flask import current_app

from ...extensions import db
from ...models import AuthSession, Customer, CustomerPreference, OTPRequest
from ...services.phone import normalize_phone


class CustomerAuthService:
    @staticmethod
    def _hash_code(code):
        secret = current_app.config["SECRET_KEY"].encode()
        return hmac.new(secret, str(code).encode(), hashlib.sha256).hexdigest()

    @staticmethod
    def _hash_token(token):
        return hashlib.sha256(token.encode()).hexdigest()

    @staticmethod
    def request_otp(raw_phone, purpose="login"):
        phone = normalize_phone(raw_phone)
        if not phone:
            raise ValueError("phone is required")

        now = datetime.now(timezone.utc)
        recent = (
            OTPRequest.query
            .filter(
                OTPRequest.phone == phone,
                OTPRequest.created_at >= now - timedelta(minutes=15),
            )
            .count()
        )
        if recent >= 3:
            raise ValueError("too many OTP requests; try again later")

        code = f"{secrets.randbelow(1_000_000):06d}"
        otp = OTPRequest(
            phone=phone,
            purpose=purpose,
            code_hash=CustomerAuthService._hash_code(code),
            expires_at=now + timedelta(minutes=5),
            attempts=0,
            status="pending",
        )
        db.session.add(otp)
        db.session.commit()

        result = {
            "otp_request_id": otp.id,
            "expires_at": otp.expires_at.isoformat(),
            "phone": phone,
        }
        if current_app.debug:
            result["debug_code"] = code
        return result

    @staticmethod
    def verify_otp(otp_request_id, raw_code, device_id=None):
        now = datetime.now(timezone.utc)
        otp = db.session.get(OTPRequest, int(otp_request_id))
        if otp is None:
            raise LookupError("OTP request not found")
        if otp.status != "pending":
            raise ValueError("OTP request is no longer pending")
        if otp.expires_at < now:
            otp.status = "expired"
            db.session.commit()
            raise ValueError("OTP has expired")
        if otp.attempts >= 5:
            otp.status = "blocked"
            db.session.commit()
            raise ValueError("too many verification attempts")

        otp.attempts += 1
        expected = CustomerAuthService._hash_code(raw_code)
        if not hmac.compare_digest(otp.code_hash, expected):
            if otp.attempts >= 5:
                otp.status = "blocked"
            db.session.commit()
            raise ValueError("invalid OTP")

        otp.status = "verified"
        customer = Customer.query.filter_by(phone_normalized=otp.phone).first()
        if customer is None:
            customer = Customer(
                phone_normalized=otp.phone,
                status="active",
                created_via="otp",
            )
            db.session.add(customer)
            db.session.flush()
            db.session.add(CustomerPreference(customer_id=customer.id, locale="ar"))

        access_token = secrets.token_urlsafe(32)
        refresh_token = secrets.token_urlsafe(48)
        session = AuthSession(
            customer_id=customer.id,
            access_token_hash=CustomerAuthService._hash_token(access_token),
            refresh_token_hash=CustomerAuthService._hash_token(refresh_token),
            device_id=device_id,
            expires_at=now + timedelta(days=30),
        )
        db.session.add(session)
        db.session.commit()

        return {
            "customer_id": customer.id,
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_at": session.expires_at.isoformat(),
        }
