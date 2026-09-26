from ...extensions import db
from ...models import Customer, CustomerAddress
from ...services.phone import normalize_phone


class CustomerService:
    @staticmethod
    def update_profile(customer_id, payload):
        customer = db.session.get(Customer, customer_id)
        if customer is None:
            raise LookupError("customer not found")
        if "name" in payload:
            customer.name = (payload["name"] or "").strip() or None
        if "email" in payload:
            customer.email = (payload["email"] or "").strip() or None
        if "city_id" in payload:
            customer.city_id = payload["city_id"]
        if "city_area_id" in payload:
            from ...models import CityArea
            area_id = payload["city_area_id"] or None
            area = db.session.get(CityArea, area_id) if area_id else None
            if area_id and (area is None or not area.is_active):
                raise ValueError("المنطقة داخل المدينة غير موجودة.")
            if area and customer.city_id and area.city_id != customer.city_id:
                raise ValueError("المنطقة داخل المدينة لا تتبع مدينة العميل.")
            customer.city_area_id = area_id
        db.session.commit()
        return CustomerService.serialize(customer)

    @staticmethod
    def add_address(customer_id, payload):
        customer = db.session.get(Customer, customer_id)
        if customer is None:
            raise LookupError("customer not found")
        phone = normalize_phone(payload.get("phone") or customer.phone_normalized)
        if not payload.get("recipient_name") or not phone or not payload.get("city_id"):
            raise ValueError("recipient_name, phone and city_id are required")

        if payload.get("is_default"):
            CustomerAddress.query.filter_by(customer_id=customer_id, is_default=True).update({"is_default": False})

        city_id = int(payload["city_id"])
        city_area_id = int(payload["city_area_id"]) if payload.get("city_area_id") else None
        if city_area_id:
            from ...models import CityArea
            area = db.session.get(CityArea, city_area_id)
            if area is None or not area.is_active or area.city_id != city_id:
                raise ValueError("المنطقة داخل المدينة غير صحيحة لهذه المدينة.")

        address = CustomerAddress(
            customer_id=customer_id,
            recipient_name=str(payload["recipient_name"]).strip(),
            phone=phone,
            country_id=payload.get("country_id"),
            city_id=city_id,
            city_area_id=city_area_id,
            district=(payload.get("district") or "").strip() or None,
            street=(payload.get("street") or "").strip() or None,
            landmark=(payload.get("landmark") or "").strip() or None,
            lat=payload.get("lat"),
            lng=payload.get("lng"),
            is_default=bool(payload.get("is_default", False)),
        )
        db.session.add(address)
        db.session.commit()
        return {
            "id": address.id,
            "recipient_name": address.recipient_name,
            "phone": address.phone,
            "city_id": address.city_id,
            "city_area_id": address.city_area_id,
            "district": address.district,
            "street": address.street,
            "landmark": address.landmark,
            "is_default": address.is_default,
        }

    @staticmethod
    def serialize(customer):
        return {
            "id": customer.id,
            "phone_normalized": customer.phone_normalized,
            "name": customer.name,
            "email": customer.email,
            "city_id": customer.city_id,
            "city_area_id": customer.city_area_id,
            "status": customer.status,
        }
