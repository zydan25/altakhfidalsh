from decimal import Decimal

from app.extensions import db
from app.models import (
    Category,
    CategoryFilterDefinition,
    CategoryFilterValue,
    Currency,
    Color,
    Size,
    InventoryLocation,
    Product,
    ProductFilterValue,
    ProductMedia,
    ProductVariant,
    ProductCategory,
    StockInventory,
    MediaAsset,
    SideCategory,
    SideCategoryCircle,
    ProductSideCategoryCircle,
)
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
    import json
    from app.models import Hashtag, Trend, TrendProduct, ProductHashtag, AppSetting

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

        db.session.add(
            AppSetting(
                group_code="trends",
                key="display_settings",
                value=json.dumps({
                    "hero_card_width": 292,
                    "hero_card_height": 196,
                    "product_height": 101,
                    "title_font_size": 19,
                    "badge_text": "HOT",
                }, ensure_ascii=False),
                value_type="json",
            )
        )
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
        assert payload["ui"]["hero_card_width"] == 292
        assert payload["ui"]["hero_card_height"] == 196
        assert payload["ui"]["product_height"] == 101
        assert payload["ui"]["title_font_size"] == 19
        assert payload["ui"]["badge_text"] == "HOT"
        assert len(payload["products"]) == 3
        assert CatalogService.is_trend_timer_expired(
            trend, datetime(2026, 9, 26, 12, 1, 59, tzinfo=timezone.utc)
        ) is False
        assert CatalogService.is_trend_timer_expired(
            trend, datetime(2026, 9, 26, 12, 2, tzinfo=timezone.utc)
        ) is True


def test_public_trends_page_exposes_global_settings_and_hashtags(app, client):
    from app.models import AppSetting, Hashtag

    with app.app_context():
        first = Hashtag(
            name="angelcore",
            slug="angelcore",
            display_name="#Angelcore",
            is_active=True,
        )
        second = Hashtag(
            name="timelessblack",
            slug="timelessblack",
            display_name="#TimelessBlack",
            is_active=True,
        )
        db.session.add_all([first, second])
        db.session.add(
            AppSetting(
                group_code="trends",
                key="display_settings",
                value='{"title_color":"#ff00aa","tabs_font_size":19,"pull_text":"اسحب الآن"}',
                value_type="json",
            )
        )
        db.session.commit()

        response = client.get("/api/v1/catalog/trends")
        assert response.status_code == 200
        payload = response.get_json()
        ids = {item["id"] for item in payload["hashtags"]}
        assert {first.id, second.id}.issubset(ids)
        assert payload["settings"]["title_color"] == "#ff00aa"
        assert payload["settings"]["tabs_font_size"] == 19
        assert payload["settings"]["pull_text"] == "اسحب الآن"


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


def test_product_side_category_references_follow_nested_category_root(app):
    with app.app_context():
        root = Category(name="نساء", slug="women-server-source", display_style="circle")
        child = Category(name="ملابس نساء", slug="women-clothes-server-source", display_style="circle")
        other_root = Category(name="رجال", slug="men-server-source", display_style="circle")
        db.session.add_all([root, child, other_root])
        db.session.flush()
        child.parent_id = root.id

        women_side = CatalogService.create_side_category({
            "root_category_id": root.id,
            "name": "دوائر النساء",
            "slug": "women-side-server",
        })
        women_circle = CatalogService.create_side_category_circle(
            women_side["id"],
            {"name": "دائرة فساتين", "slug": "women-dresses-server"},
        )
        men_side = CatalogService.create_side_category({
            "root_category_id": other_root.id,
            "name": "دوائر الرجال",
            "slug": "men-side-server",
        })
        men_circle = CatalogService.create_side_category_circle(
            men_side["id"],
            {"name": "دائرة قمصان", "slug": "men-shirts-server"},
        )

        result = CatalogService.product_side_category_references([child.id])
        circle_ids = {
            circle["id"]
            for side in result
            for circle in side["circles"]
        }
        assert women_circle["id"] in circle_ids
        assert men_circle["id"] not in circle_ids


def test_product_side_category_references_endpoint_uses_category_ids(app, client):
    with app.app_context():
        root = Category(name="نساء", slug="women-endpoint-source", display_style="circle")
        child = Category(name="ملابس نساء", slug="women-child-endpoint-source", display_style="circle", parent_id=None)
        db.session.add_all([root, child])
        db.session.flush()
        child.parent_id = root.id

        side = CatalogService.create_side_category({
            "root_category_id": root.id,
            "name": "نساء endpoint",
            "slug": "women-endpoint-side",
        })
        circle = CatalogService.create_side_category_circle(
            side["id"],
            {"name": "دائرة endpoint", "slug": "endpoint-circle-source"},
        )

        response = client.get(
            "/api/v1/catalog/reference/product-side-categories?category_id=%s" % child.id
        )
        assert response.status_code == 200
        sides = response.get_json()["items"]
        matched = next(row for row in sides if row["id"] == side["id"])
        assert any(row["id"] == circle["id"] for row in matched["circles"])


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


def test_public_results_scope_categories_side_circles_and_dynamic_filters(app, client):
    with app.app_context():
        currency = Currency(
            code="SAR",
            name_ar="ريال سعودي",
            decimals=2,
            is_base=True,
        )
        root = Category(name="نساء", slug="results-women", display_style="circle")
        child_one = Category(
            name="فساتين",
            slug="results-dresses",
            parent_id=None,
            display_style="circle",
        )
        child_two = Category(
            name="أحذية",
            slug="results-shoes",
            parent_id=None,
            display_style="circle",
        )
        db.session.add_all([currency, root, child_one, child_two])
        db.session.flush()
        child_one.parent_id = root.id
        child_two.parent_id = root.id

        color_filter = CategoryFilterDefinition(
            category_id=child_one.id,
            name="اللون",
            filter_type="color",
            sort_order=1,
        )
        second_color_filter = CategoryFilterDefinition(
            category_id=child_two.id,
            name="اللون",
            filter_type="color",
            sort_order=1,
        )
        db.session.add_all([color_filter, second_color_filter])
        db.session.flush()
        red = CategoryFilterValue(
            filter_id=color_filter.id,
            label="أحمر",
            slug="red-results",
            sort_order=1,
        )
        blue = CategoryFilterValue(
            filter_id=second_color_filter.id,
            label="أزرق",
            slug="blue-results",
            sort_order=1,
        )
        green = CategoryFilterValue(
            filter_id=color_filter.id,
            label="أخضر",
            slug="green-results-unused",
            sort_order=2,
        )

        first = Product(
            sku="RESULT-SCOPE-001",
            name="فستان أحمر",
            slug="result-scope-001",
            base_currency_id=currency.id,
            base_price=100,
            status="published",
            is_active=True,
        )
        second = Product(
            sku="RESULT-SCOPE-002",
            name="حذاء",
            slug="result-scope-002",
            base_currency_id=currency.id,
            base_price=120,
            status="published",
            is_active=True,
        )
        db.session.add_all([first, second])
        db.session.flush()

        color = Color(name="أحمر", hex_code="#ff0000", sort_order=1)
        size = Size(group="نساء", code="M", label="M", sort_order=1)
        db.session.add_all([color, size])
        db.session.flush()
        db.session.add(
            ProductVariant(
                product_id=first.id,
                sku="RESULT-SCOPE-001-M-RED",
                color_id=color.id,
                size_id=size.id,
            )
        )
        db.session.flush()

        db.session.add_all([
            ProductCategory(
                product_id=first.id,
                category_id=child_one.id,
                is_primary=True,
            ),
            ProductCategory(
                product_id=second.id,
                category_id=child_two.id,
                is_primary=True,
            ),
            red,
            blue,
            green,
        ])
        db.session.flush()

        db.session.add_all([
            ProductFilterValue(
                product_id=first.id,
                filter_value_id=red.id,
            ),
            ProductFilterValue(
                product_id=second.id,
                filter_value_id=blue.id,
            ),
        ])
        db.session.commit()

        side = CatalogService.create_side_category({
            "root_category_id": root.id,
            "name": "التنسيقات",
            "slug": "results-side",
        })
        circle_one = CatalogService.create_side_category_circle(
            side["id"],
            {"name": "فساتين", "slug": "results-side-dresses"},
        )
        circle_two = CatalogService.create_side_category_circle(
            side["id"],
            {"name": "أحذية", "slug": "results-side-shoes"},
        )
        CatalogService.set_product_side_category_circles(first.id, [circle_one["id"]])
        CatalogService.set_product_side_category_circles(second.id, [circle_two["id"]])

        circle_feed_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={
                "side_category_id": side["id"],
                "circle_id": circle_one["id"],
            },
        )
        assert circle_feed_response.status_code == 200
        circle_product_ids = {
            item["id"] for item in circle_feed_response.get_json()["items"]
        }
        assert circle_product_ids == {first.id}

        # The customer app opens a side circle by circle ID only.
        direct_circle_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={"circle_id": circle_one["id"]},
        )
        assert direct_circle_response.status_code == 200
        direct_circle_product_ids = {
            item["id"] for item in direct_circle_response.get_json()["items"]
        }
        assert direct_circle_product_ids == {first.id}

        circle_filter_response = client.get(
            f"/api/v1/catalog/products/filters?circle_id={circle_one['id']}"
        )
        assert circle_filter_response.status_code == 200
        circle_filters = circle_filter_response.get_json()["items"]
        assert any(
            value["id"] == red.id
            for group in circle_filters
            for value in group["values"]
        )
        assert any(
            value["id"] == green.id
            for group in circle_filters
            for value in group["values"]
        )
        assert any(
            value["id"] == -(1_000_000 + color.id)
            for group in circle_filters
            for value in group["values"]
        )
        assert any(
            value["id"] == -(2_000_000 + size.id)
            for group in circle_filters
            for value in group["values"]
        )

        category_filter_response = client.get(
            f"/api/v1/catalog/products/filters?category_ids={root.id}"
        )
        assert category_filter_response.status_code == 200
        category_filters = category_filter_response.get_json()["items"]
        assert any(
            value["id"] == red.id
            for group in category_filters
            for value in group["values"]
        )
        # Filter options come from the server taxonomy, not product assignments.
        assert any(
            value["id"] == green.id
            for group in category_filters
            for value in group["values"]
        )

        root_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={
                "category_id": root.id,
                "filter_value_ids": str(red.id),
            },
        )
        assert root_response.status_code == 200
        root_ids = {item["id"] for item in root_response.get_json()["items"]}
        assert root_ids == {first.id}

        union_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={
                "category_ids": f"{child_one.id},{child_two.id}",
            },
        )
        assert union_response.status_code == 200
        union_ids = {item["id"] for item in union_response.get_json()["items"]}
        assert union_ids == {first.id, second.id}

        same_group_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={
                "category_ids": f"{child_one.id},{child_two.id}",
                "filter_value_ids": f"{red.id},{blue.id}",
            },
        )
        assert same_group_response.status_code == 200
        same_group_ids = {
            item["id"] for item in same_group_response.get_json()["items"]
        }
        assert same_group_ids == {first.id, second.id}

        side_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={"side_category_id": side["id"]},
        )
        assert side_response.status_code == 200
        side_ids = {item["id"] for item in side_response.get_json()["items"]}
        assert side_ids == {first.id, second.id}

        circle_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={"circle_id": circle_one["id"]},
        )
        assert circle_response.status_code == 200
        circle_ids = {item["id"] for item in circle_response.get_json()["items"]}
        assert circle_ids == {first.id}

        color_filtered_response = client.get(
            "/api/v1/catalog/products/feed",
            query_string={
                "circle_id": circle_one["id"],
                "filter_value_ids": str(-(1_000_000 + color.id)),
            },
        )
        assert color_filtered_response.status_code == 200
        color_filtered_ids = {
            item["id"] for item in color_filtered_response.get_json()["items"]
        }
        assert color_filtered_ids == {first.id}

def test_product_detail_uses_customer_pricing_group_and_selected_currency(app):
    from datetime import datetime, timezone
    from app.models import (
        Country,
        Region,
        City,
        CityArea,
        Customer,
        CustomerPricingAssignment,
        ExchangeRate,
        PricingGroup,
    )

    with app.app_context():
        country = Country(code="YE", name_ar="اليمن")
        db.session.add(country)
        db.session.flush()
        region = Region(country_id=country.id, code="NORTH", name="الشمال")
        db.session.add(region)
        db.session.flush()
        city = City(region_id=region.id, code="IBB", name="إب")
        db.session.add(city)
        db.session.flush()
        area = CityArea(city_id=city.id, code="CENTER", name="الوسط", direction="north")
        db.session.add(area)

        sar = Currency(
            code="SAR",
            symbol="ر.س",
            name_ar="الريال السعودي",
            decimals=2,
            is_base=True,
        )
        yer = Currency(
            code="YER",
            symbol="﷼",
            name_ar="الريال اليمني",
            decimals=0,
            is_base=False,
        )
        db.session.add_all([sar, yer])
        db.session.flush()

        group = PricingGroup(
            name="عميل YER",
            default_currency_id=yer.id,
            priority=100,
            percent_markup=Decimal("10"),
            fixed_markup_sar=Decimal("5"),
            decimals=0,
            is_default=True,
        )
        db.session.add(group)
        db.session.flush()

        customer = Customer(
            phone_normalized="967771234599",
            city_id=city.id,
            city_area_id=area.id,
        )
        db.session.add(customer)
        db.session.flush()
        db.session.add(
            CustomerPricingAssignment(
                customer_id=customer.id,
                pricing_group_id=group.id,
                priority=100,
            )
        )
        db.session.add(
            ExchangeRate(
                base_currency_id=sar.id,
                quote_currency_id=yer.id,
                rate=Decimal("700"),
                valid_from=datetime.now(timezone.utc),
            )
        )

        category = Category(name="تفاصيل التسعير", slug="pricing-detail-regression")
        db.session.add(category)
        db.session.flush()
        product = Product(
            sku="DETAIL-PRICING-001",
            name="منتج تفاصيل التسعير",
            slug="detail-pricing-001",
            base_currency_id=sar.id,
            base_price=Decimal("100"),
            status="published",
            is_active=True,
        )
        db.session.add(product)
        db.session.flush()
        db.session.add(
            ProductCategory(
                product_id=product.id,
                category_id=category.id,
                is_primary=True,
            )
        )
        db.session.commit()

        snapshot = CatalogService.get_product(
            product.id,
            customer_id=customer.id,
            currency_id=yer.id,
        )
        priced = snapshot["product"]

        # 100 SAR * 700 = 70,000 YER; +10% = 7,000; +5 SAR = 3,500.
        assert Decimal(priced["display_price"]) == Decimal("80500")
        assert priced["display_currency"]["code"] == "YER"

