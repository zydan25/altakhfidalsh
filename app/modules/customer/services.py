from ...extensions import db
from ...models import Customer, CustomerAddress, Country, City, CityArea
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
    def update_address(customer_id, address_id, payload):
        address = db.session.get(CustomerAddress, address_id)
        if address is None or address.customer_id != customer_id or not address.is_active:
            raise LookupError("address not found")
        city_id = int(payload.get("city_id", address.city_id)) if payload.get("city_id", address.city_id) else None
        if not city_id or db.session.get(City, city_id) is None:
            raise ValueError("المدينة غير صحيحة.")
        country_id = payload.get("country_id", address.country_id)
        if country_id not in (None, "") and db.session.get(Country, int(country_id)) is None:
            raise ValueError("الدولة غير صحيحة.")
        area_id = payload.get("city_area_id", address.city_area_id)
        area_id = int(area_id) if area_id not in (None, "") else None
        if area_id:
            area = db.session.get(CityArea, area_id)
            if area is None or not area.is_active or area.city_id != city_id:
                raise ValueError("المنطقة داخل المدينة غير صحيحة لهذه المدينة.")
        if payload.get("is_default"):
            CustomerAddress.query.filter(
                CustomerAddress.customer_id == customer_id,
                CustomerAddress.is_default.is_(True),
                CustomerAddress.id != address.id,
            ).update({"is_default": False})
        address.recipient_name = str(payload.get("recipient_name", address.recipient_name)).strip()
        address.phone = normalize_phone(payload.get("phone") or address.phone)
        address.country_id = int(country_id) if country_id not in (None, "") else None
        address.city_id = city_id
        address.city_area_id = area_id
        address.district = str(payload.get("district", address.district) or "").strip() or None
        address.street = str(payload.get("street", address.street) or "").strip() or None
        address.landmark = str(payload.get("landmark", address.landmark) or "").strip() or None
        address.lat = payload.get("lat", address.lat)
        address.lng = payload.get("lng", address.lng)
        if "is_default" in payload:
            address.is_default = bool(payload["is_default"])
        db.session.commit()
        return CustomerService.serialize_address(address)

    @staticmethod
    def delete_address(customer_id, address_id):
        address = db.session.get(CustomerAddress, address_id)
        if address is None or address.customer_id != customer_id or not address.is_active:
            raise LookupError("address not found")
        was_default = address.is_default
        address.is_active = False
        address.is_default = False
        if was_default:
            replacement = (
                CustomerAddress.query
                .filter(
                    CustomerAddress.customer_id == customer_id,
                    CustomerAddress.is_active.is_(True),
                    CustomerAddress.id != address.id,
                )
                .order_by(CustomerAddress.id.desc())
                .first()
            )
            if replacement:
                replacement.is_default = True
        db.session.commit()
        return {"ok": True}

    @staticmethod
    def serialize_address(address):
        return {
            "id": address.id,
            "recipient_name": address.recipient_name,
            "phone": address.phone,
            "country_id": address.country_id,
            "city_id": address.city_id,
            "city_area_id": address.city_area_id,
            "district": address.district,
            "street": address.street,
            "landmark": address.landmark,
            "lat": str(address.lat) if address.lat is not None else None,
            "lng": str(address.lng) if address.lng is not None else None,
            "is_default": bool(address.is_default),
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
