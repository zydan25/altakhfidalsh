from flask import request

from . import api_bp
from ...extensions import db
from ...models import City, Country, Region


@api_bp.get("/countries")
def countries():
    rows = Country.query.filter_by(is_active=True).order_by(Country.name_ar).all()
    return {"items": [{"id": x.id, "code": x.code, "name_ar": x.name_ar, "name_en": x.name_en, "phone_code": x.phone_code} for x in rows]}


@api_bp.post("/countries")
def create_country():
    payload = request.get_json(silent=True) or {}
    code = (payload.get("code") or "").strip().upper()
    name = (payload.get("name_ar") or "").strip()
    if not code or not name:
        return {"error": "invalid_country", "detail": "code and name_ar are required"}, 400
    if Country.query.filter_by(code=code).first():
        return {"error": "invalid_country", "detail": "country code already exists"}, 400
    row = Country(code=code, name_ar=name, name_en=payload.get("name_en"), phone_code=payload.get("phone_code"))
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "code": row.code, "name_ar": row.name_ar}}, 201


@api_bp.get("/regions")
def regions():
    country_id = request.args.get("country_id", type=int)
    query = Region.query.filter_by(is_active=True)
    if country_id:
        query = query.filter_by(country_id=country_id)
    rows = query.order_by(Region.sort_order, Region.name).all()
    return {"items": [{"id": x.id, "country_id": x.country_id, "code": x.code, "name": x.name, "sort_order": x.sort_order} for x in rows]}


@api_bp.post("/regions")
def create_region():
    payload = request.get_json(silent=True) or {}
    try:
        country_id = int(payload["country_id"])
        code = str(payload["code"]).strip().upper()
        name = str(payload["name"]).strip()
    except (KeyError, ValueError):
        return {"error": "invalid_region", "detail": "country_id, code and name are required"}, 400
    if db.session.get(Country, country_id) is None:
        return {"error": "invalid_region", "detail": "country not found"}, 400
    row = Region(country_id=country_id, code=code, name=name, sort_order=int(payload.get("sort_order", 0)))
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "country_id": row.country_id, "code": row.code, "name": row.name}}, 201


@api_bp.get("/cities")
def cities():
    region_id = request.args.get("region_id", type=int)
    query = City.query.filter_by(is_active=True)
    if region_id:
        query = query.filter_by(region_id=region_id)
    rows = query.order_by(City.sort_order, City.name).all()
    return {"items": [{"id": x.id, "region_id": x.region_id, "code": x.code, "name": x.name, "sort_order": x.sort_order} for x in rows]}


@api_bp.post("/cities")
def create_city():
    payload = request.get_json(silent=True) or {}
    try:
        region_id = int(payload["region_id"])
        code = str(payload["code"]).strip().upper()
        name = str(payload["name"]).strip()
    except (KeyError, ValueError):
        return {"error": "invalid_city", "detail": "region_id, code and name are required"}, 400
    if db.session.get(Region, region_id) is None:
        return {"error": "invalid_city", "detail": "region not found"}, 400
    row = City(region_id=region_id, code=code, name=name, sort_order=int(payload.get("sort_order", 0)))
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "region_id": row.region_id, "code": row.code, "name": row.name}}, 201
