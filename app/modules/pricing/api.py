from flask import request

from . import api_bp
from ...services.pricing import price_for_customer, resolve_pricing_context


@api_bp.get("/context")
def context():
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
        context, result = price_for_customer(
            base_price_sar=__import__("decimal").Decimal(str(payload["base_price_sar"])),
            customer_id=payload.get("customer_id"),
            city_id=payload.get("city_id"),
            currency_id=payload.get("currency_id"),
        )
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "invalid_quote", "detail": str(exc)}, 400
    return {
        "context": {
            "pricing_group_id": context.pricing_group_id,
            "pricing_group_name": context.pricing_group_name,
            "currency_id": context.currency_id,
            "currency_code": context.currency_code,
            "source": context.source,
        },
        "price": {
            "base_sar": str(result.base_sar),
            "fx_rate": str(result.fx_rate),
            "converted": str(result.converted),
            "percent_add": str(result.percent_add),
            "fixed_add": str(result.fixed_add),
            "final": str(result.final),
        },
    }
