from decimal import Decimal, InvalidOperation
from flask import request
from . import api_bp
from ..services.pricing import PricingRule, calculate_customer_price

@api_bp.post("/pricing/preview")
def pricing_preview():
    payload = request.get_json(silent=True) or {}
    try:
        result = calculate_customer_price(
            Decimal(str(payload["base_price_sar"])),
            Decimal(str(payload["fx_rate"])),
            PricingRule(
                Decimal(str(payload.get("percent_markup", "0"))),
                Decimal(str(payload.get("fixed_markup", "0"))),
                int(payload.get("decimals", 2)),
            ),
            override_percent=(Decimal(str(payload["override_percent"])) if payload.get("override_percent") is not None else None),
            override_fixed=(Decimal(str(payload["override_fixed"])) if payload.get("override_fixed") is not None else None),
        )
    except (KeyError, ValueError, InvalidOperation) as exc:
        return {"error": "invalid_payload", "detail": str(exc)}, 400

    return {
        "base_sar": str(result.base_sar),
        "fx_rate": str(result.fx_rate),
        "converted": str(result.converted),
        "percent_add": str(result.percent_add),
        "fixed_add": str(result.fixed_add),
        "final": str(result.final),
    }
