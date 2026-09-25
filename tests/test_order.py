from decimal import Decimal
from datetime import datetime, timezone

from app.extensions import db
from app.models import (
    Category, City, Country, Currency, Customer, CustomerAddress,
    ExchangeRate, InventoryLocation, OrderItemOption, Product, ProductCategory,
    ProductVariant, PricingGroup, PricingGroupRule, Region, StockInventory,
)
from app.modules.commerce.services import CommerceService


def test_order_uses_customer_city_pricing_and_snapshots(app):
    with app.app_context():
        country = Country(code="YE", name_ar="اليمن")
        db.session.add(country)
        db.session.flush()
        region = Region(country_id=country.id, code="NORTH", name="الشمال")
        db.session.add(region)
        db.session.flush()
        city = City(region_id=region.id, code="IBB", name="إب")
        db.session.add(city)

        sar = Currency(code="SAR", symbol="ر.س", name_ar="الريال السعودي", decimals=2, is_base=True)
        yer = Currency(code="YER", symbol="﷼", name_ar="الريال اليمني", decimals=0, is_base=False)
        db.session.add_all([sar, yer])
        db.session.flush()

        group = PricingGroup(name="YER group", default_currency_id=yer.id, priority=1, is_default=True)
        db.session.add(group)
        db.session.flush()
        db.session.add(PricingGroupRule(
            group_id=group.id, currency_id=yer.id, percent_markup=Decimal('10'),
            fixed_markup=Decimal('5'), decimals=0,
        ))
        db.session.add(ExchangeRate(
            base_currency_id=sar.id, quote_currency_id=yer.id, rate=Decimal('700'),
            valid_from=datetime.now(timezone.utc),
        ))

        customer = Customer(phone_normalized="967771234568", city_id=city.id)
        db.session.add(customer)
        db.session.flush()
        address = CustomerAddress(customer_id=customer.id, recipient_name="عميل", phone="967771234568", city_id=city.id, street="شارع تجريبي", is_default=True)
        db.session.add(address)

        category = Category(name="Test", slug="test")
        db.session.add(category)
        db.session.flush()
        product = Product(sku="ORD-TEST", name="Order Product", slug="order-product", base_currency_id=sar.id, base_price=Decimal("100"), status="published")
        db.session.add(product)
        db.session.flush()
        db.session.add(ProductCategory(product_id=product.id, category_id=category.id, is_primary=True))
        variant = ProductVariant(product_id=product.id, sku="ORD-TEST-V1")
        db.session.add(variant)
        db.session.flush()
        location = InventoryLocation(name="Main", code="ORD-MAIN")
        db.session.add(location)
        db.session.flush()
        db.session.add(StockInventory(location_id=location.id, variant_id=variant.id, on_hand=5, reserved=0, available=5))
        db.session.commit()

        order = CommerceService.create_order({
            'customer_id': customer.id,
            'address_id': address.id,
            'currency_id': yer.id,
            'items': [{
                'variant_id': variant.id,
                'qty': 2,
                'selected_options': {'اللون': 'أسود', 'المقاس': 'XL'},
            }],
        })

        assert order['currency_id'] == yer.id
        assert order['pricing_group_id'] == group.id
        assert order['address_snapshot']['city_id'] == city.id
        assert Decimal(order['subtotal']) == Decimal('154010')
        assert Decimal(order['total']) == Decimal('154010')
        order_row = __import__("app.models", fromlist=["Order"]).Order.query.filter_by(id=order['id']).first()
        assert Decimal(order_row.markup_percent) == Decimal('10')
        assert Decimal(order_row.markup_fixed) == Decimal('5')
        item_row = __import__("app.models", fromlist=["OrderItem"]).OrderItem.query.filter_by(order_id=order['id']).first()
        assert Decimal(item_row.markup_percent) == Decimal('10')
        assert Decimal(item_row.markup_fixed) == Decimal('5')
        stock = StockInventory.query.filter_by(variant_id=variant.id, location_id=location.id).first()
        assert stock.reserved == 2
        assert stock.available == 3