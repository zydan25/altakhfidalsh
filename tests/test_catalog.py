from decimal import Decimal

from app.extensions import db
from app.models import Category, Currency, InventoryLocation, Product, ProductMedia, ProductVariant, ProductCategory, StockInventory, MediaAsset, SideCategory, SideCategoryCircle, ProductSideCategoryCircle
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
        db.session.flush()
        db.session.add(ProductCategory(product_id=product.id, category_id=root.id, is_primary=True))
        db.session.commit()

        assigned = CatalogService.set_product_side_category_circles(product.id, [circle["id"]])
        assert assigned == [circle["id"]]
        assert CatalogService.list_product_side_category_circles(product.id) == [circle["id"]]

        config = CatalogService.product_reference_data(product.id)
        assert any(x["id"] == side["id"] for x in config["side_categories"])
        assert config["selected_side_category_circle_ids"] == [circle["id"]]

        CatalogService.delete_category(child.id)
        CatalogService.delete_category(root.id)
        assert db.session.get(Category, root.id).is_active is False
        assert db.session.get(SideCategory, side["id"]).is_active is False
        assert db.session.get(SideCategoryCircle, circle["id"]).is_active is False



def test_public_trend_exposes_countdown_and_overlay_metadata(app):
    from datetime import datetime, timezone
    from app.models import Hashtag, Trend, TrendProduct, ProductHashtag

    with app.app_context():
        currency = Currency(code="SAR", name_ar="ريال سعودي", decimals=2, is_base=True)
        hashtag = Hashtag(name="مؤقت", slug="timed-trend", display_name="#مؤقت")
        asset = MediaAsset(
            storage_key="trends/timer.webp",
            url="/media/trends/timer.webp",
            mime_type="image/webp",
            width=1200,
            height=500,
            size_bytes=10,
        )
        db.session.add_all([currency, hashtag, asset])
        db.session.flush()

        products = []
        for idx in range(3):
            product = Product(
                sku=f"TREND-TIMER-00{idx + 1}",
                name=f"منتج ترند {idx + 1}",
                slug=f"trend-timer-00{idx + 1}",
                base_currency_id=currency.id,
                base_price=50 + idx,
                status="published",
            )
            db.session.add(product)
            db.session.flush()
            db.session.add(ProductHashtag(product_id=product.id, hashtag_id=hashtag.id))
            products.append(product)

        trend = Trend(
            hashtag_id=hashtag.id,
            promo_text="عرض محدود",
            duration_days=1,
            background_asset_id=asset.id,
            status="active",
            timer_value=2,
            timer_unit="minutes",
            timer_started_at=datetime(2026, 9, 26, 12, 0, tzinfo=timezone.utc),
            overlay_text="خصم اليوم",
            overlay_text_color="#ffffff",
            overlay_background_color="#7c3aed",
            is_active=True,
        )
        db.session.add(trend)
        db.session.flush()
        db.session.add_all([
            TrendProduct(trend_id=trend.id, product_id=product.id, slot=slot)
            for slot, product in enumerate(products)
        ])
        db.session.commit()

        payload = CatalogService.serialize_public_trend(trend)
        assert payload["timer"]["enabled"] is True
        assert payload["timer"]["seconds"] == 120
        assert payload["timer"]["ends_at"] == "2026-09-26T12:02:00+00:00"
        assert payload["overlay"]["text"] == "خصم اليوم"
        assert payload["overlay"]["text_color"] == "#ffffff"
        assert payload["overlay"]["background_color"] == "#7c3aed"
        assert len(payload["products"]) == 3
        assert CatalogService.is_trend_timer_expired(
            trend, datetime(2026, 9, 26, 12, 1, 59, tzinfo=timezone.utc)
        ) is False
        assert CatalogService.is_trend_timer_expired(
            trend, datetime(2026, 9, 26, 12, 2, tzinfo=timezone.utc)
        ) is True


def test_side_category_endpoint_returns_nested_circles_for_root(app, client):
    with app.app_context():
        root = Category(name="نساء", slug="women-endpoint", display_style="circle")
        child = Category(name="ملابس نساء", slug="women-clothes-endpoint", display_style="circle")
        db.session.add_all([root, child])
        db.session.flush()
        child.parent_id = root.id
        side = CatalogService.create_side_category({
            "root_category_id": root.id,
            "name": "نساء - دوائر endpoint",
            "slug": "women-side-endpoint",
        })
        circle = CatalogService.create_side_category_circle(
            side["id"],
            {"name": "فساتين endpoint", "slug": "endpoint-dresses"},
        )

        response = client.get(
            "/api/v1/catalog/side-categories?root_category_id=%s" % root.id
        )
        assert response.status_code == 200
        items = response.get_json()["items"]
        matched_side = next(row for row in items if row["id"] == side["id"])
        assert matched_side["root_category_id"] == root.id
        assert any(row["id"] == circle["id"] for row in matched_side["circles"])


def test_product_reference_data_exposes_compatible_side_circles(app):
    with app.app_context():
        currency = Currency(code="SAR", symbol="ر.س", name_ar="ريال سعودي", decimals=2, is_base=True)
        root = Category(name="نساء", slug="women", display_style="circle")
        child = Category(name="ملابس نساء", slug="women-clothes", display_style="circle")
        grandchild = Category(name="فساتين نساء", slug="women-dresses", display_style="circle")
        other_root = Category(name="رجال", slug="men", display_style="circle")
        db.session.add_all([currency, root, child, grandchild, other_root])
        db.session.flush()
        child.parent_id = root.id
        grandchild.parent_id = child.id

        women_side = CatalogService.create_side_category({
            "root_category_id": root.id,
            "name": "دوائر ملابس النساء",
            "slug": "women-clothes-side",
        })
        women_circle = CatalogService.create_side_category_circle(
            women_side["id"],
            {"name": "فساتين قصيرة", "slug": "short-dresses"},
        )
        men_side = CatalogService.create_side_category({
            "root_category_id": other_root.id,
            "name": "دوائر ملابس الرجال",
            "slug": "men-clothes-side",
        })
        men_circle = CatalogService.create_side_category_circle(
            men_side["id"],
            {"name": "قمصان", "slug": "shirts"},
        )

        product = Product(
            sku="REF-SIDE-001",
            name="منتج مرجعي",
            slug="ref-side-001",
            base_currency_id=currency.id,
            base_price=100,
            status="draft",
        )
        db.session.add(product)
        db.session.flush()
        db.session.add(ProductCategory(product_id=product.id, category_id=grandchild.id, is_primary=True))
        db.session.commit()

        refs = CatalogService.product_reference_data(product_id=product.id)
        women = [row for row in refs["available_side_category_circles"] if row["id"] == women_circle["id"]]
        men = [row for row in refs["available_side_category_circles"] if row["id"] == men_circle["id"]]

        assert women and women[0]["compatible"] is True
        assert women[0]["root_category_id"] == root.id
        assert women[0]["side_category_id"] == women_side["id"]
        assert men and men[0]["compatible"] is False
def test_product_wizard_publish_readiness_tracks_basic_fields_and_active_variants(app):
    with app.app_context():
        currency = Currency(code="SAR", symbol="ر.س", name_ar="ريال سعودي", decimals=2, is_base=True)
        category = Category(name="جاهز للنشر", slug="publish-ready", display_style="circle")
        db.session.add_all([currency, category])
        db.session.flush()
        product = Product(
            sku="READY-001",
            name="منتج جاهز",
            slug="ready-001",
            base_currency_id=currency.id,
            base_price=100,
            status="draft",
        )
        db.session.add(product)
        db.session.flush()
        db.session.add(ProductCategory(product_id=product.id, category_id=category.id, is_primary=True))
        db.session.add(ProductVariant(product_id=product.id, sku="READY-001-A"))
        asset = MediaAsset(
            storage_key="ready.webp",
            url="/media/ready.webp",
            mime_type="image/webp",
            width=100,
            height=100,
            size_bytes=10,
        )
        db.session.add(asset)
        db.session.flush()
        db.session.add(ProductMedia(product_id=product.id, asset_id=asset.id, role="gallery"))
        db.session.commit()

        snapshot = CatalogService.wizard_snapshot(product.id)
        assert snapshot["steps"]["basics"] is True
        assert snapshot["steps"]["categories"] is True
        assert snapshot["steps"]["side-categories"] is False
        assert snapshot["steps"]["variants"] is True
        assert snapshot["steps"]["media"] is True
        assert snapshot["publishable"] is True

        product.name = ""
        db.session.commit()
        snapshot = CatalogService.wizard_snapshot(product.id)
        assert snapshot["steps"]["basics"] is False
        assert snapshot["publishable"] is False
