from flask import request

from . import api_bp
from .auth import CustomerAuthService
from .security import customer_required, current_customer
from .services import CustomerService
from .wishlist import CustomerEngagementService
from ...extensions import db
from ...models import Customer, CustomerAddress


def _authorized_customer_id():
    customer = current_customer()
    return customer.id if customer else None


@api_bp.post("/auth/request-otp")
def request_otp():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CustomerAuthService.request_otp(payload.get("phone"), payload.get("purpose", "login"))}, 201
    except ValueError as exc:
        return {"error": "otp_request_failed", "detail": str(exc)}, 400


@api_bp.post("/auth/verify-otp")
def verify_otp():
    payload = request.get_json(silent=True) or {}
    try:
        result = CustomerAuthService.verify_otp(
            int(payload["otp_request_id"]),
            str(payload["code"]),
            payload.get("device_id"),
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


@api_bp.get("/me")
@customer_required
def me():
    return {"item": CustomerService.serialize(current_customer())}


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
    return {"items": [
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
        for x in rows
    ]}


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


@api_bp.post("/me/wishlist/<int:product_id>")
@customer_required
def add_my_wishlist(product_id):
    try:
        return {"item": CustomerEngagementService.add_wishlist(current_customer().id, product_id)}, 201
    except LookupError as exc:
        return {"error": "wishlist_failed", "detail": str(exc)}, 404


@api_bp.post("/me/views/<int:product_id>")
@customer_required
def track_my_view(product_id):
    return {"item": CustomerEngagementService.track_view(current_customer().id, product_id)}


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
