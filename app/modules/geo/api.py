from flask import request

from . import api_bp
from ...security import admin_api_required
from ...extensions import db
from ...models import City, CityArea, Country, GeoDirection, Region
from .services import generate_area_code, generate_city_code


@api_bp.get("/countries")
def countries():
    rows = Country.query.filter_by(is_active=True).order_by(Country.name_ar).all()
    return {"items": [{"id": x.id, "code": x.code, "name_ar": x.name_ar, "name_en": x.name_en, "phone_code": x.phone_code} for x in rows]}


@api_bp.post("/countries")
@admin_api_required("geo.manage")
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
@admin_api_required("geo.manage")
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
    return {"items": [{"id": x.id, "region_id": x.region_id, "code": x.code, "name": x.name, "direction": x.direction, "source": x.source, "sort_order": x.sort_order} for x in rows]}


@api_bp.post("/cities")
@admin_api_required("geo.manage")
def create_city():
    payload = request.get_json(silent=True) or {}
    try:
        region_id = int(payload["region_id"])
        name = str(payload["name"]).strip()
    except (KeyError, ValueError):
        return {"error": "invalid_city", "detail": "region_id and name are required"}, 400
    region = db.session.get(Region, region_id)
    if region is None or not region.is_active or not name:
        return {"error": "invalid_city", "detail": "active region and city name are required"}, 400
    row = City(
        region_id=region_id,
        code=generate_city_code(name, region_id),
        name=name,
        direction=(payload.get("direction") or "").strip() or None,
        source=(payload.get("source") or "").strip() or "manual",
        sort_order=int(payload.get("sort_order", 0)),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "region_id": row.region_id, "code": row.code, "name": row.name}}, 201



@api_bp.get("/city-areas")
def city_areas():
    city_id = request.args.get("city_id", type=int)
    query = CityArea.query.filter_by(is_active=True)
    if city_id:
        query = query.filter_by(city_id=city_id)
    rows = query.order_by(CityArea.sort_order, CityArea.name).all()
    return {
        "items": [
            {
                "id": x.id,
                "city_id": x.city_id,
                "code": x.code,
                "name": x.name,
                "direction": x.direction,
                "source": x.source,
                "sort_order": x.sort_order,
            }
            for x in rows
        ]
    }


@api_bp.post("/city-areas")
@admin_api_required("geo.manage")
def create_city_area():
    payload = request.get_json(silent=True) or {}
    try:
        city_id = int(payload["city_id"])
        name = str(payload["name"]).strip()
    except (KeyError, ValueError):
        return {"error": "invalid_city_area", "detail": "city_id and name are required"}, 400
    city = db.session.get(City, city_id)
    if city is None or not city.is_active or not name:
        return {"error": "invalid_city_area", "detail": "active city and area name are required"}, 400
    direction_code = (payload.get("direction_code") or payload.get("direction") or "").strip().lower() or None
    direction_id = None
    if direction_code:
        direction = GeoDirection.query.filter_by(code=direction_code, is_active=True).first()
        if direction is None:
            return {"error": "invalid_city_area", "detail": "unknown direction"}, 400
        direction_id = direction.id
    row = CityArea(
        city_id=city_id,
        code=generate_area_code(name, city_id),
        name=name,
        direction=direction_code,
        direction_id=direction_id,
        source=(payload.get("source") or "").strip() or "manual",
        sort_order=int(payload.get("sort_order", 0)),
    )
    db.session.add(row)
    db.session.commit()
    return {
        "item": {
            "id": row.id,
            "city_id": row.city_id,
            "code": row.code,
            "name": row.name,
            "direction": row.direction,
            "direction_id": row.direction_id,
            "source": row.source,
        }
    }, 201


@api_bp.get("/directions")
def directions():
    rows = GeoDirection.query.filter_by(is_active=True).order_by(GeoDirection.sort_order, GeoDirection.name_ar).all()
    return {"items": [{"id": x.id, "code": x.code, "name_ar": x.name_ar} for x in rows]}
