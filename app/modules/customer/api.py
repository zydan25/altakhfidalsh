from flask import request

from . import api_bp
from .auth import CustomerAuthService
from .services import CustomerService
from ...extensions import db
from ...models import Customer, CustomerAddress


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


@api_bp.get("/customers/<int:customer_id>")
def customer(customer_id):
    item = db.session.get(Customer, customer_id)
    if item is None:
        return {"error": "not_found"}, 404
    addresses = CustomerAddress.query.filter_by(customer_id=customer_id, is_active=True).order_by(
        CustomerAddress.is_default.desc(), CustomerAddress.id
    ).all()
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


@api_bp.patch("/customers/<int:customer_id>")
def update_customer(customer_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CustomerService.serialize(CustomerService.update_profile(customer_id, payload))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.post("/customers/<int:customer_id>/addresses")
def add_address(customer_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CustomerService.add_address(customer_id, payload)}, 201
    except (ValueError, LookupError) as exc:
        return {"error": "address_creation_failed", "detail": str(exc)}, 400
