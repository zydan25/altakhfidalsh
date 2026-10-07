from werkzeug.security import check_password_hash

from flask import request

from . import api_bp
from .auth import CustomerAuthService
from .security import customer_required, current_customer
from .services import CustomerService
from .wishlist import CustomerEngagementService
from ...extensions import db
from ...services.customer_deletion import delete_customer_permanently
from ...services.phone import normalize_phone
from ...models import Customer, CustomerAddress, City, CityArea, Country, Region, Product, Review


def _authorized_customer_id():
    customer = current_customer()
    return customer.id if customer else None


@api_bp.post("/auth/check-phone")
def check_phone():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CustomerAuthService.check_phone(payload.get("phone"))}
    except ValueError as exc:
        return {"error": "phone_check_failed", "detail": str(exc)}, 400


@api_bp.post("/auth/password/login")
def password_login():
    payload = request.get_json(silent=True) or {}
    try:
        result = CustomerAuthService.password_login(
            payload.get("phone"), payload.get("password"), payload.get("device_id") or "flutter-client"
        )
        return {"item": result}
    except ValueError as exc:
        return {"error": "password_login_failed", "detail": str(exc)}, 401


@api_bp.post("/me/password")
@customer_required
def set_my_password():
    payload = request.get_json(silent=True) or {}
    try:
        return {
            "item": CustomerAuthService.set_password(
                current_customer().id,
                payload.get("new_password"),
                payload.get("current_password"),
            )
        }
    except (ValueError, LookupError) as exc:
        return {"error": "password_update_failed", "detail": str(exc)}, 400


@api_bp.post("/auth/password/request-reset")
def request_password_reset():
    payload = request.get_json(silent=True) or {}
    try:
        result = CustomerAuthService.request_otp(payload.get("phone"), "password_reset")
        return {"item": result}
    except ValueError as exc:
        return {"error": "password_reset_request_failed", "detail": str(exc)}, 400


@api_bp.post("/auth/password/reset")
def reset_password():
    payload = request.get_json(silent=True) or {}
    try:
        result = CustomerAuthService.reset_password(
            payload.get("otp_request_id"), payload.get("code"), payload.get("new_password")
        )
        return {"item": result}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "password_reset_failed", "detail": str(exc)}, 400


@api_bp.post("/auth/request-otp")
def request_otp():
    payload = request.get_json(silent=True) or {}
    try:
        result = CustomerAuthService.request_otp(
            payload.get("phone"),
            payload.get("purpose", "login"),
        )
        return {"item": result, **result}, 201
    except ValueError as exc:
        return {"error": "otp_request_failed", "detail": str(exc)}, 400


@api_bp.post("/auth/verify-otp")
def verify_otp():
    payload = request.get_json(silent=True) or {}
    try:
        request_id = payload.get("otp_request_id")
        result = CustomerAuthService.verify_otp(
            int(request_id) if request_id not in (None, "") else None,
            str(payload["code"]),
            payload.get("device_id"),
            phone=payload.get("phone"),
            registration=payload.get("registration"),
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "otp_verification_failed", "detail": str(exc)}, 400
    return {"item": result}


@api_bp.post("/auth/refresh")
def refresh():
    payload = request.get_json(silent=True) or {}
    try:
        result = CustomerAuthService.refresh(
            str(payload["refresh_token"]),
            payload.get("device_id"),
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "refresh_failed", "detail": str(exc)}, 401
    return {"item": result}


@api_bp.post("/auth/logout")
@customer_required
def logout():
    auth = request.headers.get("Authorization", "")
    token = auth[7:].strip() if auth.startswith("Bearer ") else ""
    CustomerAuthService.revoke_access(token)
    return {"ok": True}


@api_bp.post("/me/delete")
@customer_required
def delete_my_account():
    payload = request.get_json(silent=True) or {}
    if str(payload.get("confirmation") or "").strip().upper() != "DELETE":
        return {"error": "confirmation_required", "detail": "اكتب DELETE لتأكيد حذف الحساب."}, 400

    customer = current_customer()
    supplied_password = str(payload.get("password") or "")
    if customer.password_hash:
        if not supplied_password or not check_password_hash(customer.password_hash, supplied_password):
            return {"error": "invalid_password", "detail": "أدخل كلمة المرور الحالية لتأكيد حذف الحساب."}, 401

    try:
        delete_customer_permanently(customer.id)
        db.session.commit()
        return {"ok": True}
    except Exception as exc:
        db.session.rollback()
        return {"error": "account_delete_failed", "detail": str(exc)}, 400


@api_bp.get("/me")
@customer_required
def me():    return {"item": CustomerService.serialize(current_customer())}


@api_bp.post("/me/phone/change-request")
@customer_required
def request_phone_change():
    payload = request.get_json(silent=True) or {}
    customer = current_customer()
    supplied_password = str(payload.get("password") or "")
    if customer.password_hash and not check_password_hash(customer.password_hash, supplied_password):
        return {"error": "invalid_password", "detail": "كلمة المرور الحالية غير صحيحة."}, 401
    if not customer.password_hash:
        return {"error": "password_required", "detail": "أنشئ كلمة مرور للحساب أولًا ثم حدّث رقم الهاتف."}, 400

    new_phone = normalize_phone(payload.get("phone"))
    if not new_phone:
        return {"error": "phone_invalid", "detail": "أدخل رقم هاتف صحيحًا."}, 400
    if new_phone == customer.phone_normalized:
        return {"error": "phone_unchanged", "detail": "رقم الهاتف الجديد مطابق للرقم الحالي."}, 400

    owner = Customer.query.filter_by(phone_normalized=new_phone).first()
    if owner is not None and owner.id != customer.id:
        return {"error": "phone_in_use", "detail": "رقم الهاتف مستخدم بالفعل من حساب آخر."}, 409

    try:
        result = CustomerAuthService.request_otp(
            new_phone,
            purpose="phone_change",
            customer_id=customer.id,
        )
        return {"item": result}, 201
    except ValueError as exc:
        return {"error": "phone_change_request_failed", "detail": str(exc)}, 400


@api_bp.post("/me/phone/verify-change")
@customer_required
def verify_phone_change():
    payload = request.get_json(silent=True) or {}
    try:
        result = CustomerAuthService.verify_otp(
            payload.get("otp_request_id"),
            str(payload.get("code") or ""),
            device_id="flutter-client",
            phone=payload.get("phone"),
        )
        if not result.get("phone_changed"):
            return {"error": "phone_change_verification_failed", "detail": "طلب تغيير الهاتف غير صحيح."}, 400
        return {"item": result}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "phone_change_verification_failed", "detail": str(exc)}, 400


@api_bp.post("/me/referral")
@customer_required
def apply_my_referral():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CustomerService.apply_referral(current_customer().id, payload.get("code"))}
    except (ValueError, LookupError) as exc:
        return {"error": "referral_failed", "detail": str(exc)}, 400


@api_bp.get("/me/referrals")
@customer_required
def my_referrals():
    try:
        return {"item": CustomerService.referral_overview(current_customer().id)}
    except LookupError as exc:
        return {"error": "referrals_not_found", "detail": str(exc)}, 404


@api_bp.post("/me/privacy-acceptance")
@customer_required
def accept_privacy():
    customer = current_customer()
    customer.privacy_accepted_at = db.func.now()
    customer.privacy_policy_version = CustomerAuthService.PRIVACY_POLICY_VERSION
    db.session.commit()
    return {"item": {"accepted": True, "version": customer.privacy_policy_version}}


@api_bp.patch("/me")
@customer_required
def update_me():
    return {"item": CustomerService.update_profile(current_customer().id, request.get_json(silent=True) or {})}


@api_bp.get("/me/addresses")
@customer_required
def my_addresses():
    rows = CustomerAddress.query.filter_by(
        customer_id=current_customer().id,
        is_active=True,
    ).order_by(CustomerAddress.is_default.desc(), CustomerAddress.id).all()
    items = []
    for x in rows:
        city = db.session.get(City, x.city_id) if x.city_id else None
        area = db.session.get(CityArea, x.city_area_id) if x.city_area_id else None
        region = db.session.get(Region, city.region_id) if city else None
        country = db.session.get(Country, x.country_id) if x.country_id else None
        items.append({
            "id": x.id,
            "recipient_name": x.recipient_name,
            "phone": x.phone,
            "country_id": x.country_id,
            "country_name": country.name_ar if country else None,
            "region_id": region.id if region else None,
            "region_name": region.name if region else None,
            "city_id": x.city_id,
            "city_name": city.name if city else None,
            "city_area_id": x.city_area_id,
            "city_area_name": area.name if area else None,
            "district": x.district,
            "street": x.street,
            "landmark": x.landmark,
            "is_default": bool(x.is_default),
        })
    return {"items": items}


@api_bp.post("/me/addresses")
@customer_required
def add_my_address():
    try:
        return {"item": CustomerService.add_address(current_customer().id, request.get_json(silent=True) or {})}, 201
    except (ValueError, LookupError) as exc:
        return {"error": "address_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/me/wishlist")
@customer_required
def my_wishlist():
    return {"items": CustomerEngagementService.list_wishlist(current_customer().id)}


@api_bp.patch("/me/addresses/<int:address_id>")
@customer_required
def update_my_address(address_id):
    try:
        return {"item": CustomerService.update_address(current_customer().id, address_id, request.get_json(silent=True) or {})}
    except (ValueError, LookupError) as exc:
        return {"error": "address_update_failed", "detail": str(exc)}, 400


@api_bp.delete("/me/addresses/<int:address_id>")
@customer_required
def delete_my_address(address_id):
    try:
        return {"item": CustomerService.delete_address(current_customer().id, address_id)}
    except LookupError as exc:
        return {"error": "address_not_found", "detail": str(exc)}, 404


@api_bp.delete("/me/wishlist/<int:product_id>")
@customer_required
def remove_my_wishlist(product_id):
    return {"item": CustomerEngagementService.remove_wishlist(current_customer().id, product_id)}


@api_bp.post("/me/wishlist/<int:product_id>")
@customer_required
def add_my_wishlist(product_id):
    try:
        return {"item": CustomerEngagementService.add_wishlist(current_customer().id, product_id)}, 201
    except LookupError as exc:
        return {"error": "wishlist_failed", "detail": str(exc)}, 404


@api_bp.post("/me/products/<int:product_id>/reviews")
@customer_required
def create_my_review(product_id):
    product = db.session.get(Product, product_id)
    if product is None or not product.is_active or product.status != "published":
        return {"error": "product_not_found"}, 404

    payload = request.get_json(silent=True) or {}
    try:
        rating = int(payload.get("rating"))
    except (TypeError, ValueError):
        return {"error": "invalid_rating", "detail": "اختر تقييمًا من 1 إلى 5."}, 400

    if rating < 1 or rating > 5:
        return {"error": "invalid_rating", "detail": "اختر تقييمًا من 1 إلى 5."}, 400

    title = str(payload.get("title") or "").strip()[:200]
    body = str(payload.get("body") or "").strip()[:4000]
    existing = Review.query.filter_by(
        product_id=product_id,
        customer_id=current_customer().id,
    ).order_by(Review.id.desc()).first()

    if existing is None:
        review = Review(
            product_id=product_id,
            customer_id=current_customer().id,
            rating=rating,
            title=title or None,
            body=body or None,
            status="approved",
            is_active=True,
        )
        db.session.add(review)
    else:
        existing.rating = rating
        existing.title = title or None
        existing.body = body or None
        existing.status = "approved"
        existing.is_active = True
        review = existing

    db.session.commit()
    return {
        "item": {
            "id": review.id,
            "product_id": review.product_id,
            "rating": review.rating,
            "title": review.title,
            "body": review.body,
            "status": review.status,
        }
    }, 201


@api_bp.post("/me/views/<int:product_id>")
@customer_required
def track_my_view(product_id):
    return {"item": CustomerEngagementService.track_view(current_customer().id, product_id)}


@api_bp.get("/me/views")
@customer_required
def my_views():
    return {"items": CustomerEngagementService.list_recent_views(
        current_customer().id,
        request.args.get("limit", 30, type=int) or 30,
    )}


@api_bp.get("/customers/<int:customer_id>")
@customer_required
def customer(customer_id):
    if customer_id != _authorized_customer_id():
        return {"error": "forbidden"}, 403
    item = db.session.get(Customer, customer_id)
    if item is None:
        return {"error": "not_found"}, 404
    addresses = CustomerAddress.query.filter_by(
        customer_id=customer_id,
        is_active=True,
    ).order_by(CustomerAddress.is_default.desc(), CustomerAddress.id).all()
    return {
        "id": item.id,
        "phone_normalized": item.phone_normalized,
        "name": item.name,
        "email": item.email,
        "city_id": item.city_id,
        "city_area_id": item.city_area_id,
        "status": item.status,
        "addresses": [
            {
                "id": x.id,
                "recipient_name": x.recipient_name,
                "phone": x.phone,
                "country_id": x.country_id,
                "city_id": x.city_id,
                "district": x.district,
                "street": x.street,
                "landmark": x.landmark,
                "is_default": x.is_default,
            }
            for x in addresses
        ],
    }
