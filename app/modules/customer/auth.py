import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from flask import current_app
from werkzeug.security import check_password_hash, generate_password_hash

from ...extensions import db
from ...models import AuthSession, Customer, CustomerAddress, CustomerPreference, Currency, City, CityArea, OTPRequest
from ...services.phone import normalize_phone, phone_candidates
from ...services.whatsapp import WhatsAppService


class CustomerAuthService:
    PRIVACY_POLICY_VERSION = "2026-10-03"

    @staticmethod
    def _find_customer(raw_phone):
        phone = normalize_phone(raw_phone)
        if not phone:
            return None, phone
        customer = Customer.query.filter_by(phone_normalized=phone).first()
        if customer is None:
            for candidate in phone_candidates(raw_phone):
                if candidate == phone:
                    continue
                customer = Customer.query.filter_by(phone_normalized=candidate).first()
                if customer is not None:
                    break
        return customer, phone

    @staticmethod
    def _hash_code(code):
        secret = current_app.config["SECRET_KEY"].encode()
        return hmac.new(secret, str(code).encode(), hashlib.sha256).hexdigest()

    @staticmethod
    def _hash_token(token):
        return hashlib.sha256(token.encode()).hexdigest()

    @staticmethod
    def _issue_session(customer, device_id=None):
        now = datetime.now(timezone.utc)
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
        db.session.flush()
        return {
            "customer_id": customer.id,
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_at": session.expires_at.isoformat(),
            "needs_onboarding": not bool(customer.onboarding_completed),
        }

    @staticmethod
    def request_otp(raw_phone, purpose="login"):
        phone = normalize_phone(raw_phone)
        if not phone:
            raise ValueError("phone is required")

        if purpose not in {"login", "register", "password_reset"}:
            purpose = "login"

        now = datetime.now(timezone.utc)
        recent = (
            OTPRequest.query
            .filter(
                OTPRequest.phone == phone,
                OTPRequest.purpose == purpose,
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

        if not current_app.testing:
            message = current_app.config.get(
                "CUSTOMER_OTP_MESSAGE",
                "رمز التحقق للتخفيض الصح: {code}",
            ).format(code=code)
            try:
                WhatsAppService.send_text(phone, message)
            except Exception as exc:
                otp.status = "send_failed"
                db.session.commit()
                raise ValueError(f"تعذر إرسال رمز التحقق عبر WhatsApp: {exc}") from exc

        result = {
            "otp_request_id": otp.id,
            "expires_at": otp.expires_at.isoformat(),
            "phone": phone,
            "purpose": purpose,
        }
        if current_app.debug:
            result["debug_code"] = code
        return result

    @staticmethod
    def check_phone(raw_phone):
        customer, phone = CustomerAuthService._find_customer(raw_phone)
        if not phone:
            raise ValueError("phone is required")
        return {
            "phone": phone,
            "exists": customer is not None,
            "has_password": bool(customer and customer.password_hash),
            "onboarding_completed": bool(customer and customer.onboarding_completed),
            "name": customer.name if customer and customer.onboarding_completed else None,
        }

    @staticmethod
    def _validate_registration(data, phone):
        name = str(data.get("name") or "").strip()
        gender = str(data.get("gender") or "").strip().lower()
        city_id = int(data.get("city_id") or 0)
        area_id = int(data.get("city_area_id") or 0) if data.get("city_area_id") else None
        currency_id = int(data.get("preferred_currency_id") or 0)
        password = str(data.get("password") or "")
        if len(name) < 2:
            raise ValueError("أدخل الاسم الكامل.")
        if gender not in {"male", "female"}:
            raise ValueError("اختر الجنس.")
        city = db.session.get(City, city_id)
        if city is None or not city.is_active:
            raise ValueError("المدينة غير صحيحة.")
        area = db.session.get(CityArea, area_id) if area_id else None
        if area_id and (area is None or not area.is_active or area.city_id != city_id):
            raise ValueError("المنطقة غير صحيحة لهذه المدينة.")
        currency = db.session.get(Currency, currency_id)
        if currency is None or not currency.is_active:
            raise ValueError("العملة غير صحيحة.")
        if len(password) < 6:
            raise ValueError("كلمة المرور يجب أن تكون 6 أحرف على الأقل.")
        return name, gender, city_id, area_id, currency_id, password

    @staticmethod
    def _create_registered_customer(phone, data):
        name, gender, city_id, area_id, currency_id, password = CustomerAuthService._validate_registration(data, phone)
        customer = Customer(
            phone_normalized=phone,
            name=name,
            gender=gender,
            city_id=city_id,
            city_area_id=area_id,
            password_hash=generate_password_hash(password),
            status="active",
            created_via="otp",
            onboarding_completed=True,
            privacy_accepted_at=datetime.now(timezone.utc),
            privacy_policy_version=CustomerAuthService.PRIVACY_POLICY_VERSION,
        )
        db.session.add(customer)
        db.session.flush()
        db.session.add(CustomerPreference(
            customer_id=customer.id,
            locale="ar",
            preferred_currency_id=currency_id,
        ))
        db.session.add(CustomerAddress(
            customer_id=customer.id,
            recipient_name=name,
            phone=phone,
            city_id=city_id,
            city_area_id=area_id,
            district=(data.get("district") or "").strip() or None,
            street=(data.get("street") or "").strip() or None,
            landmark=(data.get("landmark") or "").strip() or None,
            is_default=True,
        ))
        return customer

    @staticmethod
    def verify_otp(otp_request_id, raw_code, device_id=None, phone=None, registration=None):
        now = datetime.now(timezone.utc)
        otp = db.session.get(OTPRequest, int(otp_request_id)) if otp_request_id not in (None, "") else None
        if otp is None and phone:
            normalized_phone = normalize_phone(phone)
            if normalized_phone:
                otp = (
                    OTPRequest.query
                    .filter(
                        OTPRequest.phone == normalized_phone,
                        OTPRequest.status == "pending",
                        OTPRequest.expires_at >= now,
                    )
                    .order_by(OTPRequest.created_at.desc(), OTPRequest.id.desc())
                    .first()
                )
        if otp is None:
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
        expected = CustomerAuthService._hash_code(raw_code)
        if not hmac.compare_digest(otp.code_hash, expected):
            if otp.attempts >= 5:
                otp.status = "blocked"
            db.session.commit()
            raise ValueError("invalid OTP")

        otp.status = "verified"
        customer, canonical_phone = CustomerAuthService._find_customer(otp.phone)
        if customer is not None and customer.phone_normalized != canonical_phone:
            # Normalize legacy local records when they are successfully authenticated.
            existing_canonical = Customer.query.filter_by(
                phone_normalized=canonical_phone
            ).first()
            if existing_canonical is None:
                customer.phone_normalized = canonical_phone

        if otp.purpose == "password_reset":
            if customer is None:
                raise LookupError("الحساب غير موجود.")
            return {
                "reset_verified": True,
                "customer_id": customer.id,
                "phone": customer.phone_normalized,
            }

        if customer is None:
            if registration is None:
                # Legacy OTP login remains supported; the next client screen completes onboarding.
                customer = Customer(
                    phone_normalized=otp.phone,
                    status="active",
                    created_via="otp",
                    onboarding_completed=False,
                )
                db.session.add(customer)
                db.session.flush()
                db.session.add(CustomerPreference(customer_id=customer.id, locale="ar"))
            else:
                customer = CustomerAuthService._create_registered_customer(otp.phone, registration)

        result = CustomerAuthService._issue_session(customer, device_id)
        db.session.commit()
        return result

    @staticmethod
    def password_login(raw_phone, password, device_id=None):
        customer, phone = CustomerAuthService._find_customer(raw_phone)
        if customer is None or not customer.password_hash:
            raise ValueError("لا يوجد دخول بكلمة مرور لهذا الرقم.")
        if not check_password_hash(customer.password_hash, str(password or "")):
            raise ValueError("رقم الهاتف أو كلمة المرور غير صحيحة.")
        result = CustomerAuthService._issue_session(customer, device_id)
        db.session.commit()
        return result

    @staticmethod
    def reset_password(otp_request_id, raw_code, new_password):
        now = datetime.now(timezone.utc)
        otp = db.session.get(OTPRequest, int(otp_request_id))
        if otp is None or otp.purpose != "password_reset":
            raise LookupError("طلب استعادة كلمة المرور غير موجود.")
        if otp.status != "pending":
            if otp.status != "verified":
                raise ValueError("رمز التحقق غير صالح.")
        if otp.status == "pending":
            expires_at = otp.expires_at if otp.expires_at.tzinfo else otp.expires_at.replace(tzinfo=timezone.utc)
            if expires_at < now:
                otp.status = "expired"
                db.session.commit()
                raise ValueError("انتهت صلاحية رمز التحقق.")
            otp.attempts += 1
            if not hmac.compare_digest(otp.code_hash, CustomerAuthService._hash_code(raw_code)):
                if otp.attempts >= 5:
                    otp.status = "blocked"
                db.session.commit()
                raise ValueError("رمز التحقق غير صحيح.")
            otp.status = "verified"

        password = str(new_password or "")
        if len(password) < 6:
            raise ValueError("كلمة المرور يجب أن تكون 6 أحرف على الأقل.")
        customer, canonical_phone = CustomerAuthService._find_customer(otp.phone)
        if customer is None:
            raise LookupError("الحساب غير موجود.")
        customer.password_hash = generate_password_hash(password)
        customer.onboarding_completed = bool(
            customer.name and customer.city_id and customer.privacy_accepted_at
        )
        db.session.commit()
        return {"ok": True, "customer_id": customer.id}

    @staticmethod
    def set_password(customer_id, new_password, current_password=None):
        password = str(new_password or "")
        if len(password) < 6:
            raise ValueError("كلمة المرور يجب أن تكون 6 أحرف على الأقل.")
        customer = db.session.get(Customer, int(customer_id))
        if customer is None:
            raise LookupError("الحساب غير موجود.")
        if customer.password_hash:
            current = str(current_password or "")
            if not current or not check_password_hash(customer.password_hash, current):
                raise ValueError("كلمة المرور الحالية غير صحيحة.")
        customer.password_hash = generate_password_hash(password)
        customer.onboarding_completed = bool(
            customer.name and customer.city_id and customer.privacy_accepted_at
        )
        db.session.commit()
        return {"ok": True}

    @staticmethod
    def refresh(refresh_token, device_id=None):
        token_hash = CustomerAuthService._hash_token(refresh_token)
        session = AuthSession.query.filter_by(refresh_token_hash=token_hash).first()
        if session is None or session.revoked_at is not None:
            raise ValueError("invalid refresh token")
        now = datetime.now(timezone.utc)
        if session.expires_at <= now:
            session.revoked_at = now
            db.session.commit()
            raise ValueError("refresh session expired")
        new_access = secrets.token_urlsafe(32)
        new_refresh = secrets.token_urlsafe(48)
        session.access_token_hash = CustomerAuthService._hash_token(new_access)
        session.refresh_token_hash = CustomerAuthService._hash_token(new_refresh)
        session.device_id = device_id or session.device_id
        db.session.commit()
        return {
            "customer_id": session.customer_id,
            "access_token": new_access,
            "refresh_token": new_refresh,
            "expires_at": session.expires_at.isoformat(),
        }

    @staticmethod
    def revoke_access(token):
        session = AuthSession.query.filter_by(access_token_hash=CustomerAuthService._hash_token(token)).first()
        if session is None:
            return False
        session.revoked_at = datetime.now(timezone.utc)
        db.session.commit()
        return True
