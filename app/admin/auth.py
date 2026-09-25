from datetime import datetime, timezone
from functools import wraps

from flask import current_app, redirect, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

from ..extensions import db
from ..models import Admin, OTPRequest
from ..services.phone import normalize_phone
from ..services.whatsapp import WhatsAppService


class AdminAuthService:
    @staticmethod
    def _hash_code(code):
        secret = current_app.config["SECRET_KEY"].encode()
        return hmac.new(secret, str(code).encode(), hashlib.sha256).hexdigest()

    @staticmethod
    def login(username, password):
        admin = Admin.query.filter_by(username=username, is_active=True).first()
        if admin is None or not admin.password_hash or not check_password_hash(admin.password_hash, password):
            raise ValueError("invalid credentials")
        admin.last_login = datetime.now(timezone.utc)
        db.session.commit()
        session.clear()
        session["admin_id"] = admin.id
        session["admin_username"] = admin.username
        return {"id": admin.id, "username": admin.username}


    @staticmethod
    def request_otp(raw_phone):
        phone = normalize_phone(raw_phone)
        if not phone:
            raise ValueError("phone is required")
        admin = Admin.query.filter_by(phone=phone, is_active=True).first()
        if admin is None:
            raise ValueError("admin phone is not authorized")
        now = datetime.now(timezone.utc)
        recent = OTPRequest.query.filter(
            OTPRequest.phone == phone,
            OTPRequest.purpose == "admin_login",
            OTPRequest.created_at >= now - timedelta(minutes=15),
        ).count()
        if recent >= 3:
            raise ValueError("too many OTP requests; try again later")
        code = f"{secrets.randbelow(1_000_000):06d}"
        otp = OTPRequest(
            phone=phone,
            purpose="admin_login",
            code_hash=AdminAuthService._hash_code(code),
            expires_at=now + timedelta(minutes=5),
            attempts=0,
            status="pending",
        )
        db.session.add(otp)
        db.session.commit()
        message = current_app.config.get("ADMIN_OTP_MESSAGE", "رمز دخول لوحة إدارة التخفيض: {code}").format(code=code)
        try:
            WhatsAppService.send_text(phone, message)
        except Exception as exc:
            otp.status = "send_failed"
            db.session.commit()
            raise ValueError(f"تعذر إرسال رمز التحقق عبر WhatsApp: {exc}") from exc
        return {
            "otp_request_id": otp.id,
            "expires_at": otp.expires_at.isoformat(),
            "phone": phone,
            "debug_code": code if current_app.debug else None,
        }

    @staticmethod
    def verify_otp(otp_request_id, raw_code):
        now = datetime.now(timezone.utc)
        otp = db.session.get(OTPRequest, int(otp_request_id))
        if otp is None or otp.purpose != "admin_login":
            raise LookupError("OTP request not found")
        if otp.status != "pending":
            raise ValueError("OTP request is no longer pending")
        expires_at = otp.expires_at if otp.expires_at.tzinfo else otp.expires_at.replace(tzinfo=timezone.utc)
        if expires_at < now:
            otp.status = "expired"
            db.session.commit()
            raise ValueError("OTP has expired")
        if otp.attempts >= 5:
            otp.status = "blocked"
            db.session.commit()
            raise ValueError("too many verification attempts")
        otp.attempts += 1
        if not hmac.compare_digest(otp.code_hash, AdminAuthService._hash_code(raw_code)):
            if otp.attempts >= 5:
                otp.status = "blocked"
            db.session.commit()
            raise ValueError("invalid OTP")
        otp.status = "verified"
        admin = Admin.query.filter_by(phone=otp.phone, is_active=True).first()
        if admin is None:
            db.session.rollback()
            raise ValueError("admin is not authorized")
        admin.last_login = now
        db.session.commit()
        session.clear()
        session["admin_id"] = admin.id
        session["admin_username"] = admin.username
        return {"id": admin.id, "username": admin.username, "phone": admin.phone}

    @staticmethod
    def logout():
        session.clear()

    @staticmethod
    def bootstrap(username, password):
        if not username or not password or len(password) < 8:
            raise ValueError("username and password (8+ chars) are required")
        admin = Admin.query.filter_by(username=username).first()
        if admin is None:
            admin = Admin(username=username, status="active")
            db.session.add(admin)
        admin.password_hash = generate_password_hash(password)
        admin.is_active = True
        db.session.commit()
        return {"id": admin.id, "username": admin.username}


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        bypass = current_app.config.get("ADMIN_DEV_BYPASS", False)
        if bypass:
            return view(*args, **kwargs)
        if not session.get("admin_id"):
            return redirect(url_for("admin.login", next=request.path))
        return view(*args, **kwargs)

    return wrapped
