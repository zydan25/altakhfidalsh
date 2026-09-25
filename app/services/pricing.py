from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Optional

from sqlalchemy import and_, or_

from ..extensions import db
from ..models import (
    City,
    Currency,
    Customer,
    CustomerPricingAssignment,
    ExchangeRate,
    PricingGroup,
    PricingGroupCity,
    PricingGroupRule,
)


@dataclass(frozen=True)
class PricingRule:
    percent_markup: Decimal = Decimal("0")
    fixed_markup: Decimal = Decimal("0")
    decimals: int = 2
    rounding_rule: str = "nearest"


@dataclass(frozen=True)
class PriceResult:
    base_sar: Decimal
    fx_rate: Decimal
    converted: Decimal
    percent_add: Decimal
    fixed_add: Decimal
    final: Decimal


@dataclass(frozen=True)
class PricingContext:
    pricing_group_id: int
    pricing_group_name: str
    currency_id: int
    currency_code: str
    rule: PricingRule
    override_percent: Optional[Decimal]
    override_fixed: Optional[Decimal]
    source: str


def round_money(value: Decimal, decimals: int, rounding_rule: str = "nearest") -> Decimal:
    quantum = Decimal("1") / (Decimal("10") ** decimals)
    rounding = ROUND_HALF_UP
    if rounding_rule == "down":
        from decimal import ROUND_DOWN
        rounding = ROUND_DOWN
    elif rounding_rule == "up":
        from decimal import ROUND_UP
        rounding = ROUND_UP
    return value.quantize(quantum, rounding=rounding)


def calculate_customer_price(
    base_price_sar: Decimal,
    fx_rate: Decimal,
    rule: PricingRule,
    *,
    override_percent: Optional[Decimal] = None,
    override_fixed: Optional[Decimal] = None,
) -> PriceResult:
    base = Decimal(base_price_sar)
    rate = Decimal(fx_rate)
    percent = rule.percent_markup if override_percent is None else Decimal(override_percent)
    fixed = rule.fixed_markup if override_fixed is None else Decimal(override_fixed)
    converted = base * rate
    percent_add = converted * percent / Decimal("100")
    final = round_money(
        converted + percent_add + fixed,
        rule.decimals,
        rule.rounding_rule,
    )
    return PriceResult(base, rate, converted, percent_add, fixed, final)


def _active_window_clause(model, now):
    return and_(
        or_(model.starts_at.is_(None), model.starts_at <= now),
        or_(model.ends_at.is_(None), model.ends_at >= now),
    )


def resolve_pricing_context(
    *,
    customer_id: Optional[int] = None,
    city_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    now: Optional[datetime] = None,
) -> PricingContext:
    now = now or datetime.now(timezone.utc)
    customer = db.session.get(Customer, customer_id) if customer_id else None
    effective_city_id = city_id or (customer.city_id if customer else None)

    assignment = None
    if customer:
        assignment = (
            CustomerPricingAssignment.query
            .filter(
                CustomerPricingAssignment.customer_id == customer.id,
                CustomerPricingAssignment.is_active.is_(True),
                _active_window_clause(CustomerPricingAssignment, now),
            )
            .order_by(CustomerPricingAssignment.priority.desc(), CustomerPricingAssignment.id.desc())
            .first()
        )

    group = None
    source = "default"
    override_percent = None
    override_fixed = None

    if assignment:
        group = db.session.get(PricingGroup, assignment.pricing_group_id)
        if group:
            source = "customer"
            override_percent = assignment.percent_override
            override_fixed = assignment.fixed_override

    if group is None and effective_city_id:
        city = db.session.get(City, effective_city_id)
        city_assignment = (
            PricingGroupCity.query
            .filter(
                PricingGroupCity.city_id == effective_city_id,
                PricingGroupCity.is_active.is_(True),
                _active_window_clause(PricingGroupCity, now),
            )
            .order_by(PricingGroupCity.priority.desc(), PricingGroupCity.id.desc())
            .first()
        )
        if city_assignment is None and city:
            city_assignment = (
                PricingGroupCity.query
                .filter(
                    PricingGroupCity.region_id == city.region_id,
                    PricingGroupCity.city_id.is_(None),
                    PricingGroupCity.is_active.is_(True),
                    _active_window_clause(PricingGroupCity, now),
                )
                .order_by(PricingGroupCity.priority.desc(), PricingGroupCity.id.desc())
                .first()
            )
            if city_assignment:
                source = "region"
        else:
            if city_assignment:
                source = "city"

        if city_assignment:
            group = db.session.get(PricingGroup, city_assignment.pricing_group_id)

    if group is None:
        group = (
            PricingGroup.query
            .filter(
                PricingGroup.is_default.is_(True),
                PricingGroup.is_active.is_(True),
                _active_window_clause(PricingGroup, now),
            )
            .order_by(PricingGroup.priority.desc(), PricingGroup.id.desc())
            .first()
        )

    if group is None or not group.is_active or not (
        (group.starts_at is None or group.starts_at <= now)
        and (group.ends_at is None or group.ends_at >= now)
    ):
        raise LookupError("No active pricing group is configured")

    target_currency_id = currency_id or group.default_currency_id
    if target_currency_id is None:
        raise LookupError("Pricing group has no default currency")

    rule = (
        PricingGroupRule.query
        .filter_by(group_id=group.id, currency_id=target_currency_id)
        .first()
    )
    if rule is None:
        raise LookupError("No pricing rule exists for the requested currency")

    currency = db.session.get(Currency, target_currency_id)
    if currency is None:
        raise LookupError("Requested currency was not found")

    return PricingContext(
        pricing_group_id=group.id,
        pricing_group_name=group.name,
        currency_id=currency.id,
        currency_code=currency.code,
        rule=PricingRule(
            percent_markup=Decimal(rule.percent_markup),
            fixed_markup=Decimal(rule.fixed_markup),
            decimals=rule.decimals,
            rounding_rule=rule.rounding_rule,
        ),
        override_percent=Decimal(override_percent) if override_percent is not None else None,
        override_fixed=Decimal(override_fixed) if override_fixed is not None else None,
        source=source,
    )


def resolve_exchange_rate(
    *,
    base_currency_id: int,
    quote_currency_id: int,
    now: Optional[datetime] = None,
) -> Decimal:
    if base_currency_id == quote_currency_id:
        return Decimal("1")

    now = now or datetime.now(timezone.utc)
    row = (
        ExchangeRate.query
        .filter(
            ExchangeRate.base_currency_id == base_currency_id,
            ExchangeRate.quote_currency_id == quote_currency_id,
            ExchangeRate.valid_from <= now,
            or_(ExchangeRate.valid_to.is_(None), ExchangeRate.valid_to >= now),
        )
        .order_by(ExchangeRate.valid_from.desc(), ExchangeRate.id.desc())
        .first()
    )
    if row is None:
        raise LookupError("No active exchange rate exists for the requested currency")
    return Decimal(row.rate)


def price_for_customer(
    *,
    base_price_sar: Decimal,
    customer_id: Optional[int] = None,
    city_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    now: Optional[datetime] = None,
):
    context = resolve_pricing_context(
        customer_id=customer_id,
        city_id=city_id,
        currency_id=currency_id,
        now=now,
    )
    base_currency = Currency.query.filter_by(code="SAR").first()
    if base_currency is None:
        raise LookupError("SAR base currency is not configured")
    fx_rate = resolve_exchange_rate(
        base_currency_id=base_currency.id,
        quote_currency_id=context.currency_id,
        now=now,
    )
    return context, calculate_customer_price(
        Decimal(base_price_sar),
        fx_rate,
        context.rule,
        override_percent=context.override_percent,
        override_fixed=context.override_fixed,
    )
