from datetime import datetime, timezone
from decimal import Decimal
from ...extensions import db
from ...models import (
    City,
    CityArea,
    Currency,
    Customer,
    CustomerPricingAssignment,
    ExchangeRate,
    PricingGroup,
    PricingGroupCity,
    PricingGroupRule,
    Region,
)
from ...services.pricing import price_for_customer


def _dt(value):
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


class PricingAdminService:
    @staticmethod
    def create_currency(payload):
        code = str(payload["code"]).strip().upper()
        if Currency.query.filter_by(code=code).first():
            raise ValueError("currency code already exists")
        row = Currency(
            code=code,
            symbol=(payload.get("symbol") or "").strip() or None,
            name_ar=str(payload["name_ar"]).strip(),
            decimals=int(payload.get("decimals", 2)),
            is_base=bool(payload.get("is_base", False)),
        )
        if row.decimals < 0 or row.decimals > 6:
            raise ValueError("decimals must be between 0 and 6")
        if row.is_base and Currency.query.filter_by(is_base=True).first():
            raise ValueError("only one base currency is allowed")
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "code": row.code, "name_ar": row.name_ar}

    @staticmethod
    def create_exchange_rate(payload):
        sar = Currency.query.filter_by(code="SAR", is_active=True).first()
        if sar is None:
            raise ValueError("SAR base currency is not configured")
        base_id = sar.id
        quote_id = int(payload["quote_currency_id"])
        rate = Decimal(str(payload["rate"]))
        quote = db.session.get(Currency, quote_id)
        if quote is None or not quote.is_active:
            raise ValueError("currency not found")
        if quote_id == base_id:
            raise ValueError("quote currency must differ from SAR")
        if rate <= 0:
            raise ValueError("rate must be positive")
        row = ExchangeRate(
            base_currency_id=base_id,
            quote_currency_id=quote_id,
            rate=rate,
            source=payload.get("source"),
            valid_from=_dt(payload["valid_from"]),
            valid_to=_dt(payload.get("valid_to")),
        )
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "base_currency_id": row.base_currency_id, "quote_currency_id": row.quote_currency_id, "rate": str(row.rate)}

    @staticmethod
    def create_group(payload):
        if bool(payload.get("is_default", False)) and PricingGroup.query.filter_by(is_default=True, is_active=True).first():
            raise ValueError("an active default pricing group already exists")

        group = PricingGroup(
            name=str(payload["name"]).strip(),
            description=(payload.get("description") or "").strip() or None,
            default_currency_id=int(payload["default_currency_id"]) if payload.get("default_currency_id") else None,
            percent_markup=Decimal(str(payload.get("percent_markup", 0) or 0)),
            fixed_markup_sar=Decimal(str(payload.get("fixed_markup_sar", payload.get("fixed_markup", 0)) or 0)),
            rounding_rule=str(payload.get("rounding_rule", "nearest")),
            decimals=int(payload.get("decimals", 2)),
            priority=int(payload.get("priority", 0)),
            starts_at=_dt(payload.get("starts_at")),
            ends_at=_dt(payload.get("ends_at")),
            is_default=bool(payload.get("is_default", False)),
        )
        db.session.add(group)
        db.session.flush()

        rules = payload.get("rules") or []
        if not rules and group.default_currency_id:
            rules = [{"currency_id": group.default_currency_id}]
        for raw in rules:
            currency_id = int(raw["currency_id"])
            if db.session.get(Currency, currency_id) is None:
                raise ValueError("currency not found")
            db.session.add(PricingGroupRule(
                group_id=group.id,
                currency_id=currency_id,
                percent_markup=Decimal(str(raw.get("percent_markup", 0))),
                fixed_markup=Decimal(str(raw.get("fixed_markup", 0))),
                rounding_rule=str(raw.get("rounding_rule", "nearest")),
                decimals=int(raw.get("decimals", 2)),
            ))
        db.session.commit()
        return {"id": group.id, "name": group.name, "default_currency_id": group.default_currency_id}

    @staticmethod
    def assign_location(payload):
        group_id = int(payload["pricing_group_id"])
        if db.session.get(PricingGroup, group_id) is None:
            raise ValueError("pricing group not found")
        city_id = int(payload["city_id"]) if payload.get("city_id") else None
        region_id = int(payload["region_id"]) if payload.get("region_id") else None
        area_id = int(payload["area_id"]) if payload.get("area_id") else None
        targets = [x for x in (city_id, region_id, area_id) if x is not None]
        if len(targets) != 1:
            raise ValueError("exactly one of city_id, region_id or area_id is required")
        if city_id is not None and db.session.get(City, city_id) is None:
            raise ValueError("city not found")
        if region_id is not None and db.session.get(Region, region_id) is None:
            raise ValueError("region not found")
        if area_id is not None and db.session.get(CityArea, area_id) is None:
            raise ValueError("city area not found")
        row = PricingGroupCity(
            city_id=city_id,
            region_id=region_id,
            area_id=area_id,
            pricing_group_id=group_id,
            priority=int(payload.get("priority", 0)),
            starts_at=_dt(payload.get("starts_at")),
            ends_at=_dt(payload.get("ends_at")),
        )
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "city_id": row.city_id, "region_id": row.region_id, "area_id": row.area_id, "pricing_group_id": row.pricing_group_id}

    @staticmethod
    def assign_customer(payload):
        group_id = int(payload["pricing_group_id"])
        customer_id = int(payload["customer_id"])
        if db.session.get(PricingGroup, group_id) is None or db.session.get(__import__("app.models", fromlist=["Customer"]).Customer, customer_id) is None:
            raise ValueError("pricing group or customer not found")
        row = CustomerPricingAssignment(
            customer_id=customer_id,
            pricing_group_id=group_id,
            percent_override=Decimal(str(payload["percent_override"])) if payload.get("percent_override") is not None else None,
            fixed_override=Decimal(str(payload["fixed_override"])) if payload.get("fixed_override") is not None else None,
            priority=int(payload.get("priority", 0)),
            starts_at=payload.get("starts_at"),
            ends_at=payload.get("ends_at"),
        )
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "customer_id": customer_id, "pricing_group_id": group_id, "percent_override": str(row.percent_override) if row.percent_override is not None else None, "fixed_override": str(row.fixed_override) if row.fixed_override is not None else None}

    @staticmethod
    def preview(payload):
        context, result = price_for_customer(
            base_price_sar=Decimal(str(payload["base_price_sar"])),
            customer_id=payload.get("customer_id"),
            city_id=payload.get("city_id"),
            area_id=payload.get("area_id"),
            currency_id=payload.get("currency_id"),
        )
        return {
            "context": {
                "pricing_group_id": context.pricing_group_id,
                "pricing_group_name": context.pricing_group_name,
                "currency_id": context.currency_id,
                "currency_code": context.currency_code,
                "source": context.source,
                "percent_markup": str(context.rule.percent_markup),
                "fixed_markup": str(context.rule.fixed_markup),
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
