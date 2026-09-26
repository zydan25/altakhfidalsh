from dataclasses import dataclass
from decimal import Decimal
from typing import Optional

from sqlalchemy import or_

from ..extensions import db
from ..models import City, CityArea, ShippingMethod, ShippingRate, ShippingRule, ShippingRuleTarget
from .pricing import resolve_exchange_rate


@dataclass(frozen=True)
class ShippingQuote:
    rate_id: Optional[int]
    method_id: Optional[int]
    method_name: Optional[str]
    price_sar: Decimal
    price_display: Decimal
    free: bool
    source: str
    min_order_sar: Optional[Decimal]
    max_order_sar: Optional[Decimal]
    free_over_sar: Optional[Decimal]
    base_price_sar: Decimal = Decimal("0")
    adjustment_sar: Decimal = Decimal("0")
    applied_rule_ids: tuple = ()


class ShippingService:
    @staticmethod
    def resolve_rate(
        *,
        customer_id: Optional[int] = None,
        city_id: Optional[int] = None,
        area_id: Optional[int] = None,
        region_id: Optional[int] = None,
        subtotal_sar: Decimal = Decimal("0"),
    ):
        city = db.session.get(City, city_id) if city_id else None
        if area_id:
            area = db.session.get(CityArea, area_id)
            if area is None or not area.is_active:
                raise ValueError("city area not found")
            if city_id and area.city_id != city_id:
                raise ValueError("city area does not belong to city")
            city_id = city_id or area.city_id
            city = city or db.session.get(City, area.city_id)
            region_id = region_id or (city.region_id if city else None)
        elif city:
            region_id = region_id or city.region_id

        query = (
            ShippingRate.query
            .join(ShippingMethod, ShippingMethod.id == ShippingRate.method_id)
            .filter(
                ShippingRate.is_active.is_(True),
                ShippingMethod.is_active.is_(True),
                or_(ShippingRate.customer_id.is_(None), ShippingRate.customer_id == customer_id),
                or_(ShippingRate.city_area_id.is_(None), ShippingRate.city_area_id == area_id),
                or_(ShippingRate.city_id.is_(None), ShippingRate.city_id == city_id),
                or_(ShippingRate.region_id.is_(None), ShippingRate.region_id == region_id),
            )
        )

        candidates = []
        for row in query.all():
            min_sar = row.min_order_sar if row.min_order_sar is not None else row.min_order
            max_sar = row.max_order_sar if row.max_order_sar is not None else row.max_order
            price_sar = row.price_sar if row.price_sar is not None else row.price
            free_over = row.free_over_sar if row.free_over_sar is not None else row.free_over
            if min_sar is not None and subtotal_sar < Decimal(min_sar):
                continue
            if max_sar is not None and subtotal_sar > Decimal(max_sar):
                continue
            customer_score = 1 if row.customer_id is not None and row.customer_id == customer_id else 0
            area_score = 1 if row.city_area_id is not None and row.city_area_id == area_id else 0
            city_score = 1 if row.city_id is not None and row.city_id == city_id else 0
            region_score = 1 if row.region_id is not None and row.region_id == region_id else 0
            candidates.append(
                (
                    customer_score,
                    area_score,
                    city_score,
                    region_score,
                    int(row.priority or 0),
                    Decimal(min_sar) if min_sar is not None else Decimal("0"),
                    row,
                    Decimal(price_sar or 0),
                    Decimal(free_over) if free_over is not None else None,
                )
            )

        candidates.sort(key=lambda item: item[:6], reverse=True)
        if not candidates:
            return None

        _, _, _, _, _, _, row, price_sar, free_over = candidates[0]
        free = free_over is not None and subtotal_sar >= free_over
        return row, price_sar, free, free_over

    @staticmethod
    def _rule_matches(rule, *, city_id=None, area_id=None, region_id=None, subtotal_sar=Decimal("0")):
        if rule.min_order_sar is not None and subtotal_sar < Decimal(rule.min_order_sar):
            return False
        if rule.max_order_sar is not None and subtotal_sar > Decimal(rule.max_order_sar):
            return False
        if rule.applies_to_all:
            return True
        targets = ShippingRuleTarget.query.filter_by(rule_id=rule.id).all()
        for target in targets:
            if target.target_type == "area" and area_id == target.target_id:
                return True
            if target.target_type == "city" and city_id == target.target_id:
                return True
            if target.target_type == "region" and region_id == target.target_id:
                return True
        return False

    @staticmethod
    def _rule_specificity(rule, *, city_id=None, area_id=None, region_id=None):
        if rule.applies_to_all:
            return 0
        targets = ShippingRuleTarget.query.filter_by(rule_id=rule.id).all()
        levels = {
            "area": 3 if any(x.target_id == area_id for x in targets if x.target_type == "area") else 0,
            "city": 2 if any(x.target_id == city_id for x in targets if x.target_type == "city") else 0,
            "region": 1 if any(x.target_id == region_id for x in targets if x.target_type == "region") else 0,
        }
        return max(levels.values())

    @staticmethod
    def quote(
        *,
        customer_id: Optional[int] = None,
        city_id: Optional[int] = None,
        area_id: Optional[int] = None,
        region_id: Optional[int] = None,
        subtotal_sar: Decimal = Decimal("0"),
        currency_id: Optional[int] = None,
        fx_rate: Optional[Decimal] = None,
    ) -> ShippingQuote:
        resolved = ShippingService.resolve_rate(
            customer_id=customer_id,
            city_id=city_id,
            area_id=area_id,
            region_id=region_id,
            subtotal_sar=Decimal(subtotal_sar),
        )
        if resolved is None:
            return ShippingQuote(None, None, None, Decimal("0"), Decimal("0"), True, "default", None, None, None)

        row, price_sar, free, free_over = resolved
        method = db.session.get(ShippingMethod, row.method_id)
        display_rate = Decimal(fx_rate) if fx_rate is not None else Decimal("1")
        base_price_sar = Decimal(price_sar or 0)
        final_price_sar = Decimal("0") if free else base_price_sar
        applied_rule_ids = []
        if not free:
            city = db.session.get(City, city_id) if city_id else None
            effective_region_id = region_id or (city.region_id if city else None)
            rules = (
                ShippingRule.query
                .filter(
                    ShippingRule.method_id == row.method_id,
                    ShippingRule.is_active.is_(True),
                )
                .order_by(ShippingRule.priority.desc(), ShippingRule.id.desc())
                .all()
            )
            matched = [
                rule for rule in rules
                if ShippingService._rule_matches(
                    rule,
                    city_id=city_id,
                    area_id=area_id,
                    region_id=effective_region_id,
                    subtotal_sar=Decimal(subtotal_sar),
                )
            ]
            matched.sort(
                key=lambda rule: (
                    ShippingService._rule_specificity(
                        rule,
                        city_id=city_id,
                        area_id=area_id,
                        region_id=effective_region_id,
                    ),
                    int(rule.priority or 0),
                    rule.id,
                ),
                reverse=True,
            )
            for rule in matched:
                before = final_price_sar
                if rule.rule_type == "free_shipping":
                    final_price_sar = Decimal("0")
                elif rule.rule_type == "percent_discount":
                    final_price_sar -= final_price_sar * Decimal(rule.value or 0) / Decimal("100")
                elif rule.rule_type == "fixed_discount":
                    final_price_sar -= Decimal(rule.value or 0)
                elif rule.rule_type == "surcharge":
                    final_price_sar += Decimal(rule.value or 0)
                elif rule.rule_type == "set_price":
                    final_price_sar = Decimal(rule.value or 0)
                final_price_sar = max(Decimal("0"), final_price_sar)
                if final_price_sar != before or rule.rule_type == "free_shipping":
                    applied_rule_ids.append(rule.id)
                if rule.stop_processing or not rule.stackable:
                    break
        price_display = final_price_sar * display_rate
        return ShippingQuote(
            rate_id=row.id,
            method_id=row.method_id,
            method_name=method.name if method else None,
            price_sar=final_price_sar,
            price_display=price_display,
            free=final_price_sar == 0,
            source=(
                "customer" if row.customer_id
                else "area" if row.city_area_id
                else "city" if row.city_id
                else "region" if row.region_id
                else "default"
            ),
            min_order_sar=Decimal(row.min_order_sar if row.min_order_sar is not None else row.min_order)
                if (row.min_order_sar is not None or row.min_order is not None) else None,
            max_order_sar=Decimal(row.max_order_sar if row.max_order_sar is not None else row.max_order)
                if (row.max_order_sar is not None or row.max_order is not None) else None,
            free_over_sar=Decimal(free_over) if free_over is not None else None,
            base_price_sar=base_price_sar,
            adjustment_sar=final_price_sar - base_price_sar,
            applied_rule_ids=tuple(applied_rule_ids),
        )
