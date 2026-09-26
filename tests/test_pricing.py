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
    assert result.fixed_add == Decimal("350")
    assert result.final == Decimal("8050.00")


def test_round_money():
    assert round_money(Decimal("12.345"), 2) == Decimal("12.35")



def test_exchange_rate_can_be_read_in_reverse_direction(app):
    from datetime import datetime, timezone
    from app.extensions import db
    from app.models import Currency, ExchangeRate
    from app.services.pricing import resolve_exchange_rate

    with app.app_context():
        sar = Currency(code="SAR", name_ar="ريال سعودي", is_base=True)
        yer = Currency(code="YER", name_ar="ريال يمني")
        db.session.add_all([sar, yer])
        db.session.flush()
        db.session.add(
            ExchangeRate(
                base_currency_id=sar.id,
                quote_currency_id=yer.id,
                rate=Decimal("72"),
                valid_from=datetime.now(timezone.utc),
            )
        )
        db.session.commit()

        assert resolve_exchange_rate(
            base_currency_id=sar.id,
            quote_currency_id=yer.id,
        ) == Decimal("72")
        assert resolve_exchange_rate(
            base_currency_id=yer.id,
            quote_currency_id=sar.id,
        ) == Decimal(1) / Decimal("72")


def test_pricing_group_markup_is_independent_from_display_currency(app):
    from datetime import datetime, timezone
    from app.extensions import db
    from app.models import Currency, PricingGroup
    from app.services.pricing import price_for_customer

    with app.app_context():
        sar = Currency(code="SAR", name_ar="ريال سعودي", is_base=True, decimals=2)
        yer = Currency(code="YER", name_ar="ريال يمني", decimals=2)
        group = PricingGroup(
            name="مجموعة التجزئة",
            percent_markup=Decimal("10"),
            fixed_markup_sar=Decimal("5"),
            rounding_rule="nearest",
            decimals=2,
            is_default=True,
        )
        db.session.add_all([sar, yer, group])
        db.session.flush()
        from app.models import ExchangeRate
        db.session.add(
            ExchangeRate(
                base_currency_id=sar.id,
                quote_currency_id=yer.id,
                rate=Decimal("70"),
                valid_from=datetime.now(timezone.utc),
            )
        )
        db.session.commit()

        _, sar_result = price_for_customer(base_price_sar=Decimal("100"), currency_id=sar.id)
        _, yer_result = price_for_customer(base_price_sar=Decimal("100"), currency_id=yer.id)

        assert sar_result.final == Decimal("115.00")
        assert yer_result.final == Decimal("8050.00")


def test_city_area_has_higher_pricing_priority_than_city(app):
    from datetime import datetime, timezone
    from app.extensions import db
    from app.models import City, CityArea, Currency, PricingGroup, PricingGroupCity, Region
    from app.services.pricing import resolve_pricing_context

    with app.app_context():
        sar = Currency(code="SAR", name_ar="ريال سعودي", is_base=True)
        country = __import__("app.models", fromlist=["Country"]).Country(code="YE", name_ar="اليمن")
        region = Region(country_id=1, code="IBB", name="إب")
        city = City(region_id=1, code="IBB-C", name="إب", direction="south")
        area = CityArea(city_id=1, code="IBB-A", name="وسط المدينة", direction="center")
        group_city = PricingGroup(name="مدينة", is_active=True)
        group_area = PricingGroup(name="منطقة داخلية", is_active=True)
        db.session.add_all([sar, country])
        db.session.flush()
        region.country_id = country.id
        city.region_id = region.id
        db.session.add(region)
        db.session.flush()
        area.city_id = city.id
        db.session.add(city)
        db.session.flush()
        area.city_id = city.id
        db.session.add(area)
        db.session.flush()
        group_city.default_currency_id = sar.id
        group_area.default_currency_id = sar.id
        db.session.add_all([group_city, group_area])
        db.session.flush()
        db.session.add_all([
            PricingGroupCity(pricing_group_id=group_city.id, city_id=city.id, priority=1),
            PricingGroupCity(pricing_group_id=group_area.id, area_id=area.id, priority=1),
        ])
        db.session.commit()

        ctx = resolve_pricing_context(city_id=city.id, area_id=area.id, currency_id=sar.id)
        assert ctx.pricing_group_name == "منطقة داخلية"
