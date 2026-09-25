from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional

@dataclass(frozen=True)
class PricingRule:
    percent_markup: Decimal = Decimal("0")
    fixed_markup: Decimal = Decimal("0")
    decimals: int = 2

@dataclass(frozen=True)
class PriceResult:
    base_sar: Decimal
    fx_rate: Decimal
    converted: Decimal
    percent_add: Decimal
    fixed_add: Decimal
    final: Decimal

def round_money(value: Decimal, decimals: int) -> Decimal:
    quantum = Decimal("1") / (Decimal("10") ** decimals)
    return value.quantize(quantum, rounding=ROUND_HALF_UP)

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
    final = round_money(converted + percent_add + fixed, rule.decimals)
    return PriceResult(base, rate, converted, percent_add, fixed, final)
