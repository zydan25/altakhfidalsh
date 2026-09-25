from decimal import Decimal, InvalidOperation

from flask import request

from . import api_bp
from ..services.pricing import (
    PricingRule,
    calculate_customer_price,
    price_for_customer,
)


@api_bp.post("/pricing/preview")
def pricing_preview():
    payload = request.get_json(silent=True) or {}

    try:
        if payload.get("customer_id") is not None or payload.get("city_id") is not None:
            context, result = price_for_customer(
                base_price_sar=Decimal(str(payload["base_price_sar"])),
                customer_id=(int(payload["customer_id"]) if payload.get("customer_id") is not None else None),
                city_id=(int(payload["city_id"]) if payload.get("city_id") is not None else None),
                currency_id=(int(payload["currency_id"]) if payload.get("currency_id") is not None else None),
            )
            return {
                "pricing_group_id": context.pricing_group_id,
                "pricing_group_name": context.pricing_group_name,
                "pricing_source": context.source,
                "currency_id": context.currency_id,
                "currency_code": context.currency_code,
                "base_sar": str(result.base_sar),
                "fx_rate": str(result.fx_rate),
                "converted": str(result.converted),
                "percent_add": str(result.percent_add),
                "fixed_add": str(result.fixed_add),
                "final": str(result.final),
            }

        result = calculate_customer_price(
            Decimal(str(payload["base_price_sar"])),
            Decimal(str(payload["fx_rate"])),
            PricingRule(
                Decimal(str(payload.get("percent_markup", "0"))),
                Decimal(str(payload.get("fixed_markup", "0"))),
                int(payload.get("decimals", 2)),
                str(payload.get("rounding_rule", "nearest")),
            ),
            override_percent=(
                Decimal(str(payload["override_percent"]))
                if payload.get("override_percent") is not None
                else None
            ),
            override_fixed=(
                Decimal(str(payload["override_fixed"]))
                if payload.get("override_fixed") is not None
                else None
            ),
        )
    except (KeyError, ValueError, InvalidOperation, LookupError) as exc:
        return {"error": "invalid_pricing_context", "detail": str(exc)}, 400

    return {
        "base_sar": str(result.base_sar),
        "fx_rate": str(result.fx_rate),
        "converted": str(result.converted),
        "percent_add": str(result.percent_add),
        "fixed_add": str(result.fixed_add),
        "final": str(result.final),
    }
