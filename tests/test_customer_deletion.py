from decimal import Decimal

from app.extensions import db
from app.models import (
    Category,
    Currency,
    Customer,
    CustomerAddress,
    InventoryLocation,
    Order,
    OrderItem,
    Product,
    ProductVariant,
    ReturnItem,
    ReturnRequest,
    StockInventory,
)
from app.services.customer_deletion import delete_customer_permanently


def test_delete_customer_permanently_removes_orders_and_releases_reserved_stock(app):
    with app.app_context():
        currency = Currency(
            code="YER",
            symbol="﷼",
            name_ar="الريال اليمني",
            decimals=0,
            is_base=False,
        )
        category = Category(name="حذف العميل", slug="customer-delete-test")
        customer = Customer(
            phone_normalized="967700000001",
            name="عميل للحذف",
            city_id=None,
        )
        location = InventoryLocation(name="حذف-TEST", code="DELETE-TEST")
        db.session.add_all([currency, category, customer, location])
        db.session.flush()

        product = Product(
            sku="DELETE-CUSTOMER-PRODUCT",
            name="منتج اختبار الحذف",
            slug="delete-customer-product",
            base_currency_id=currency.id,
            base_price=Decimal("100"),
            status="published",
            is_active=True,
        )
        db.session.add(product)
        db.session.flush()
        variant = ProductVariant(
            product_id=product.id,
            sku="DELETE-CUSTOMER-VARIANT",
        )
        db.session.add(variant)
        db.session.flush()
        stock = StockInventory(
            location_id=location.id,
            variant_id=variant.id,
            on_hand=10,
            reserved=2,
            available=8,
        )
        db.session.add(stock)

        address = CustomerAddress(
            customer_id=customer.id,
            recipient_name="عميل للحذف",
            phone="967700000001",
            street="شارع الاختبار",
        )
        db.session.add(address)
        db.session.flush()

        order = Order(
            order_no="ALT-DELETE-CUSTOMER-001",
            customer_id=customer.id,
            address_snapshot={"recipient_name": "عميل للحذف"},
            currency_id=currency.id,
            fx_rate=Decimal("1"),
            markup_percent=Decimal("0"),
            markup_fixed=Decimal("0"),
            subtotal=Decimal("100"),
            discount=Decimal("0"),
            shipping=Decimal("0"),
            shipping_base_sar=Decimal("0"),
            total=Decimal("100"),
            status="processing",
            payment_status="unpaid",
            shipping_status="pending",
        )
        db.session.add(order)
        db.session.flush()
        item = OrderItem(
            order_id=order.id,
            product_id=product.id,
            variant_id=variant.id,
            stock_location_id=location.id,
            sku_snapshot=variant.sku,
            name_snapshot=product.name,
            base_price_sar=Decimal("100"),
            fx_rate=Decimal("1"),
            markup_percent=Decimal("0"),
            markup_fixed=Decimal("0"),
            sale_price_display=Decimal("100"),
            qty=2,
            total=Decimal("200"),
        )
        db.session.add(item)
        db.session.flush()
        return_request = ReturnRequest(
            order_id=order.id,
            customer_id=customer.id,
            reason="اختبار الحذف",
        )
        db.session.add(return_request)
        db.session.flush()
        db.session.add(
            ReturnItem(
                return_request_id=return_request.id,
                order_item_id=item.id,
                qty=1,
            )
        )
        db.session.commit()

        delete_customer_permanently(customer.id)
        db.session.commit()

        assert db.session.get(Customer, customer.id) is None
        assert db.session.get(CustomerAddress, address.id) is None
        assert db.session.get(Order, order.id) is None
        assert db.session.get(OrderItem, item.id) is None
        assert db.session.get(ReturnRequest, return_request.id) is None
        assert db.session.get(ReturnItem, item.id) is None
        refreshed_stock = db.session.get(StockInventory, stock.id)
        assert refreshed_stock.reserved == 0
        assert refreshed_stock.available == 10
