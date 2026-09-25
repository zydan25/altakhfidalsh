from ...extensions import db
from flask import request

from . import api_bp
from ...models import Customer, CustomerAddress


@api_bp.get("/customers/<int:customer_id>")
def customer(customer_id):
    item = db.session.get(Customer, customer_id)
    if item is None:
        return {"error": "not_found"}, 404
    addresses = CustomerAddress.query.filter_by(customer_id=customer_id, is_active=True).order_by(CustomerAddress.is_default.desc(), CustomerAddress.id).all()
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
                "city_id": x.city_id,
                "district": x.district,
                "street": x.street,
                "landmark": x.landmark,
                "is_default": x.is_default,
            }
            for x in addresses
        ],
    }
