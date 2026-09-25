from decimal import Decimal

from app.services.pricing import PricingRule, calculate_customer_price, round_money


def test_customer_price_calculation():
    result = calculate_customer_price(
        Decimal("100"),
        Decimal("70"),
        PricingRule(
            percent_markup=Decimal("10"),
            fixed_markup=Decimal("5"),
            decimals=2,
        ),
    )

    assert result.converted == Decimal("7000")
    assert result.percent_add == Decimal("700")
    assert result.final == Decimal("7705.00")


def test_round_money():
    assert round_money(Decimal("12.345"), 2) == Decimal("12.35")
