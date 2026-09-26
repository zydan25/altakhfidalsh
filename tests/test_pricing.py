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
    from app.extensions import db
    from app.models import City, CityArea, Country, Currency, PricingGroup, PricingGroupCity, Region
    from app.services.pricing import resolve_pricing_context

    with app.app_context():
        country = Country(code="YE-AREA", name_ar="اليمن")
        sar = Currency(code="SAR", name_ar="ريال سعودي", is_base=True)
        db.session.add_all([country, sar])
        db.session.flush()

        region = Region(country_id=country.id, code="IBB-AREA", name="إب")
        db.session.add(region)
        db.session.flush()

        city = City(region_id=region.id, code="IBB-C-AREA", name="إب", direction="south")
        db.session.add(city)
        db.session.flush()

        area = CityArea(city_id=city.id, code="IBB-A-AREA", name="وسط المدينة", direction="center")
        db.session.add(area)
        db.session.flush()

        group_city = PricingGroup(name="مدينة", default_currency_id=sar.id, is_active=True)
        group_area = PricingGroup(name="منطقة داخلية", default_currency_id=sar.id, is_active=True)
        db.session.add_all([group_city, group_area])
        db.session.flush()

        db.session.add_all([
            PricingGroupCity(pricing_group_id=group_city.id, city_id=city.id, priority=1),
            PricingGroupCity(pricing_group_id=group_area.id, area_id=area.id, priority=1),
        ])
        db.session.commit()

        ctx = resolve_pricing_context(city_id=city.id, area_id=area.id, currency_id=sar.id)
        assert ctx.pricing_group_name == "منطقة داخلية"



def test_shipping_rule_uses_customer_location_and_cart_tiers(app):
    from app.extensions import db
    from app.models import City, Country, Customer, Region, ShippingMethod, ShippingRate
    from app.services.shipping import ShippingService

    with app.app_context():
        country = Country(code="YE2", name_ar="اليمن")
        db.session.add(country)
        db.session.flush()
        region = Region(country_id=country.id, code="IBB2", name="إب")
        db.session.add(region)
        db.session.flush()
        city = City(region_id=region.id, code="IBB2-C", name="إب")
        customer = Customer(phone_normalized="967700000001", name="عميل اختبار", city_id=None)
        method = ShippingMethod(name="مندوب", code="courier-test")
        db.session.add_all([city, customer, method])
        db.session.flush()
        customer.city_id = city.id
        db.session.add_all([
            ShippingRate(
                method_id=method.id,
                city_id=city.id,
                min_order_sar=Decimal("0"),
                max_order_sar=Decimal("299"),
                price_sar=Decimal("25"),
                price=Decimal("25"),
                min_order=Decimal("0"),
                max_order=Decimal("299"),
                priority=1,
            ),
            ShippingRate(
                method_id=method.id,
                city_id=city.id,
                min_order_sar=Decimal("300"),
                price_sar=Decimal("15"),
                price=Decimal("15"),
                min_order=Decimal("300"),
                free_over_sar=Decimal("500"),
                free_over=Decimal("500"),
                priority=2,
            ),
            ShippingRate(
                method_id=method.id,
                customer_id=customer.id,
                price_sar=Decimal("5"),
                price=Decimal("5"),
                priority=50,
            ),
        ])
        db.session.commit()

        quote = ShippingService.quote(
            customer_id=customer.id,
            city_id=city.id,
            subtotal_sar=Decimal("120"),
        )
        assert quote.price_sar == Decimal("5")
        assert quote.source == "customer"

        quote = ShippingService.quote(
            customer_id=None,
            city_id=city.id,
            subtotal_sar=Decimal("250"),
        )
        assert quote.price_sar == Decimal("25")

        quote = ShippingService.quote(
            customer_id=None,
            city_id=city.id,
            subtotal_sar=Decimal("600"),
        )
        assert quote.free is True
        assert quote.price_display == Decimal("0")



def test_city_location_adjustment_is_applied_after_group_markup(app):
    from app.extensions import db
    from app.models import City, Country, Currency, PricingGroup, PricingLocationAdjustment, Region
    from app.services.pricing import price_for_customer

    with app.app_context():
        country = Country(code="YE-LOC", name_ar="اليمن")
        sar = Currency(code="SAR", name_ar="ريال سعودي", is_base=True)
        group = PricingGroup(
            name="أساس",
            default_currency_id=sar.id,
            percent_markup=Decimal("10"),
            fixed_markup_sar=Decimal("0"),
            is_default=True,
        )
        db.session.add_all([country, sar, group])
        db.session.flush()
        region = Region(country_id=country.id, code="LOC-R", name="إب")
        city = City(region_id=region.id, code="LOC-C", name="إب")
        db.session.add_all([region, city])
        db.session.flush()
        db.session.add(
            PricingLocationAdjustment(
                city_id=city.id,
                percent_adjustment=Decimal("-5"),
                fixed_adjustment_sar=Decimal("0"),
                priority=10,
            )
        )
        db.session.commit()

        _, result = price_for_customer(
            base_price_sar=Decimal("100"),
            city_id=city.id,
            currency_id=sar.id,
        )
        assert result.converted == Decimal("100")
        assert result.percent_add == Decimal("10")
        assert result.location_percent_add == Decimal("-5.50")
        assert result.final == Decimal("104.50")


def test_shipping_percent_rule_applies_to_selected_city(app):
    from app.extensions import db
    from app.models import City, Country, Region, ShippingMethod, ShippingRate, ShippingRule, ShippingRuleTarget
    from app.services.shipping import ShippingService

    with app.app_context():
        country = Country(code="YE-SHIP-RULE", name_ar="اليمن")
        db.session.add(country)
        db.session.flush()
        region = Region(country_id=country.id, code="SHIP-R", name="إب")
        city = City(region_id=region.id, code="SHIP-C", name="إب")
        method = ShippingMethod(name="مندوب", code="ship-rule-test")
        db.session.add_all([region, city, method])
        db.session.flush()
        db.session.add(
            ShippingRate(
                method_id=method.id,
                city_id=city.id,
                price_sar=Decimal("20"),
                price=Decimal("20"),
                priority=1,
            )
        )
        rule = ShippingRule(
            method_id=method.id,
            rule_type="percent_discount",
            min_order_sar=Decimal("100"),
            max_order_sar=Decimal("299"),
            value=Decimal("25"),
            priority=20,
            stackable=False,
            stop_processing=True,
            applies_to_all=False,
        )
        db.session.add(rule)
        db.session.flush()
        db.session.add(
            ShippingRuleTarget(rule_id=rule.id, target_type="city", target_id=city.id)
        )
        db.session.commit()

        quote = ShippingService.quote(
            city_id=city.id,
            subtotal_sar=Decimal("150"),
            fx_rate=Decimal("72"),
        )
        assert quote.base_price_sar == Decimal("20")
        assert quote.price_sar == Decimal("15")
        assert quote.price_display == Decimal("1080")
        assert quote.applied_rule_ids == (rule.id,)
