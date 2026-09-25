from decimal import Decimal

from flask import request

from . import api_bp
from .services import PricingAdminService
from ...models import Currency, ExchangeRate, PricingGroup, PricingGroupRule


@api_bp.get("/context")
def context():
    from ...services.pricing import resolve_pricing_context
    try:
        result = resolve_pricing_context(
            customer_id=request.args.get("customer_id", type=int),
            city_id=request.args.get("city_id", type=int),
            currency_id=request.args.get("currency_id", type=int),
        )
    except LookupError as exc:
        return {"error": "pricing_context_not_found", "detail": str(exc)}, 404
    return {
        "pricing_group_id": result.pricing_group_id,
        "pricing_group_name": result.pricing_group_name,
        "currency_id": result.currency_id,
        "currency_code": result.currency_code,
        "source": result.source,
        "percent_markup": str(result.rule.percent_markup),
        "fixed_markup": str(result.rule.fixed_markup),
        "decimals": result.rule.decimals,
        "rounding_rule": result.rule.rounding_rule,
    }


@api_bp.post("/quote")
def quote():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": PricingAdminService.preview(payload)}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "invalid_quote", "detail": str(exc)}, 400


@api_bp.get("/currencies")
def currencies():
    rows = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
    return {"items": [{"id": x.id, "code": x.code, "symbol": x.symbol, "name_ar": x.name_ar, "decimals": x.decimals, "is_base": x.is_base} for x in rows]}


@api_bp.post("/currencies")
def create_currency():
    try:
        return {"item": PricingAdminService.create_currency(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "currency_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/groups")
def groups():
    rows = PricingGroup.query.filter_by(is_active=True).order_by(PricingGroup.priority.desc(), PricingGroup.name).all()
    return {"items": [
        {
            "id": x.id,
            "name": x.name,
            "default_currency_id": x.default_currency_id,
            "priority": x.priority,
            "is_default": x.is_default,
            "rules": [
                {
                    "currency_id": rule.currency_id,
                    "percent_markup": str(rule.percent_markup),
                    "fixed_markup": str(rule.fixed_markup),
                    "rounding_rule": rule.rounding_rule,
                    "decimals": rule.decimals,
                }
                for rule in PricingGroupRule.query.filter_by(group_id=x.id).all()
            ],
        }
        for x in rows
    ]}


@api_bp.post("/groups")
def create_group():
    try:
        return {"item": PricingAdminService.create_group(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "pricing_group_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/exchange-rates")
def exchange_rate():
    try:
        return {"item": PricingAdminService.create_exchange_rate(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "exchange_rate_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/location-assignments")
def location_assignment():
    try:
        return {"item": PricingAdminService.assign_location(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "location_assignment_failed", "detail": str(exc)}, 400


@api_bp.post("/customer-assignments")
def customer_assignment():
    try:
        return {"item": PricingAdminService.assign_customer(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "customer_assignment_failed", "detail": str(exc)}, 400
