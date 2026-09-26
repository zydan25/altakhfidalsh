from decimal import Decimal

from app.extensions import db
from app.models import Category, Currency, InventoryLocation, Product, ProductMedia, ProductVariant, StockInventory, MediaAsset, SideCategory, SideCategoryCircle, ProductSideCategoryCircle
from app.modules.catalog.services import CatalogService


def test_product_draft_and_publish_requirements(app):
    with app.app_context():
        sar = Currency(code="SAR", symbol="ر.س", name_ar="الريال السعودي", decimals=2, is_base=True)
        db.session.add(sar)
        db.session.flush()
        category = Category(name="ملابس", slug="clothes", display_style="circle")
        db.session.add(category)
        db.session.flush()
        product = CatalogService.create_draft({
            "sku": "SHP-TEST-1", "name": "منتج تجريبي", "base_price": "100",
            "base_currency_id": sar.id, "category_ids": [category.id],
        })
        assert product['status'] == 'draft'
        created = Product.query.filter_by(sku="SHP-TEST-1").first()
        variant = ProductVariant(product_id=created.id, sku="SHP-TEST-1-BLK-M")
        db.session.add(variant)
        db.session.flush()
        location = InventoryLocation(name="Main", code="MAIN")
        db.session.add(location)
        db.session.flush()
        db.session.add(StockInventory(location_id=location.id, variant_id=variant.id, on_hand=10, reserved=0, available=10))
        asset = MediaAsset(storage_key="test.webp", url="/media/test.webp", mime_type="image/webp", width=100, height=100, size_bytes=10)
        db.session.add(asset)
        db.session.flush()
        db.session.add(ProductMedia(product_id=created.id, asset_id=asset.id, role='gallery'))
        db.session.commit()
        published = CatalogService.publish_product(created.id)
        assert published['status'] == 'published'

def test_side_category_tree_is_independent_and_root_only(app):
    with app.app_context():
        root = Category(name="نساء", slug="women", display_style="circle")
        child = Category(name="فساتين", slug="dresses", parent_id=None, display_style="circle")
        db.session.add_all([root, child])
        db.session.flush()
        child.parent_id = root.id
        db.session.commit()

        side = CatalogService.create_side_category({
            "root_category_id": root.id,
            "name": "فساتين نسائية",
            "slug": "women-dresses",
        })
        assert side["root_category_id"] == root.id

        try:
            CatalogService.create_side_category({
                "root_category_id": child.id,
                "name": "غير صالح",
            })
            assert False, "expected root-only validation"
        except ValueError as exc:
            assert "قسم رئيسي" in str(exc)

        circle = CatalogService.create_side_category_circle(
            side["id"],
            {"name": "فساتين", "slug": "dresses"},
        )
        assert circle["side_category_id"] == side["id"]

        currency = Currency(code="SAR", symbol="ر.س", name_ar="ريال سعودي", decimals=2, is_base=True)
        product = Product(
            sku="SIDE-CAT-TEST-001",
            name="منتج جانبي",
            slug="side-cat-test-001",
            base_currency_id=currency.id,
            base_price=100,
            status="published",
        )
        db.session.add(currency)
        db.session.flush()
        product.base_currency_id = currency.id
        db.session.add(product)
        db.session.commit()

        assigned = CatalogService.set_product_side_category_circles(product.id, [circle["id"]])
        assert assigned == [circle["id"]]
        assert CatalogService.list_product_side_category_circles(product.id) == [circle["id"]]

        config = CatalogService.product_reference_data(product.id)
        assert any(x["id"] == side["id"] for x in config["side_categories"])
        assert config["selected_side_category_circle_ids"] == [circle["id"]]
