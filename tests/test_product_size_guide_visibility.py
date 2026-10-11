import json

from app.extensions import db
from app.models import (
    AppSetting,
    Currency,
    Product,
    ProductSizeGuideReference,
    ProductSizeReference,
    Size,
    SizeGuide,
    SizeGuideRow,
)
from app.modules.catalog.services import CatalogService


def _create_product_with_size_guide(*, assign_guide=False, global_show=True):
    currency = Currency(
        code="SAR",
        symbol="ر.س",
        name_ar="الريال السعودي",
        decimals=2,
        is_base=True,
    )
    db.session.add(currency)
    db.session.flush()

    product = Product(
        sku="SIZE-GUIDE-TEST-001",
        name="فستان تجريبي",
        slug="size-guide-test-001",
        base_currency_id=currency.id,
        base_price=100,
        status="published",
    )
    size = Size(group="women", code="M", label="M")
    guide = SizeGuide(name="جدول مقاسات الفستان", guide_type="product")
    db.session.add_all([product, size, guide])
    db.session.flush()

    db.session.add_all([
        ProductSizeReference(product_id=product.id, size_id=size.id),
        SizeGuideRow(
            guide_id=guide.id,
            size_id=size.id,
            product_measurements={"length": 100},
            body_measurements={"chest": 90},
        ),
    ])
    if assign_guide:
        db.session.add(
            ProductSizeGuideReference(product_id=product.id, guide_id=guide.id)
        )

    db.session.add(
        AppSetting(
            group_code="storefront",
            key="product_detail_settings",
            value=json.dumps({"size_guide_show": global_show}),
            value_type="json",
        )
    )
    db.session.commit()
    return product.id, guide.id


def test_product_without_assigned_size_guide_does_not_auto_select_one(app):
    with app.app_context():
        product_id, _guide_id = _create_product_with_size_guide(
            assign_guide=False, global_show=True
        )
        item = CatalogService.get_product(product_id)

        assert item["size_guide"] is None
        assert item["size_guides"] == []
        assert item["product_detail_settings"]["size_guide_show"] is False
        assert all(
            "size_guide" not in group.get("items", [])
            for group in item["product_detail_settings"]["detail_groups"]
        )


def test_product_with_assigned_guide_respects_global_setting(app):
    with app.app_context():
        product_id, guide_id = _create_product_with_size_guide(
            assign_guide=True, global_show=True
        )
        item = CatalogService.get_product(product_id)

        assert item["size_guide"]["id"] == guide_id
        assert item["product_detail_settings"]["size_guide_show"] is True
        assert any(
            "size_guide" in group.get("items", [])
            for group in item["product_detail_settings"]["detail_groups"]
        )


def test_global_size_guide_setting_can_hide_assigned_guide(app):
    with app.app_context():
        product_id, guide_id = _create_product_with_size_guide(
            assign_guide=True, global_show=False
        )
        item = CatalogService.get_product(product_id)

        assert item["size_guide"]["id"] == guide_id
        assert item["product_detail_settings"]["size_guide_show"] is False
        assert all(
            "size_guide" not in group.get("items", [])
            for group in item["product_detail_settings"]["detail_groups"]
        )
