from app.extensions import db
from app.models import Badge, Color, Customer, CustomerAddress, Currency, MediaAsset, Product, ProductMedia, StorefrontPage, StorefrontSection, StorefrontSectionItem


def test_customer_admin_profile_and_address(client, app):
    with app.app_context():
        customer = Customer(phone_normalized="967700000001", name="عميل تجريبي", status="active")
        db.session.add(customer)
        db.session.commit()
        customer_id = customer.id

    with client.session_transaction() as session:
        session["admin_id"] = 1

    response = client.get(f"/admin/customers/{customer_id}")
    assert response.status_code == 200
    assert "عميل تجريبي" in response.get_data(as_text=True)

    response = client.post(
        f"/admin/customers/{customer_id}",
        data={
            "action": "profile",
            "name": "العميل المحدث",
            "email": "customer@example.test",
            "status": "active",
        },
    )
    assert response.status_code == 200

    with app.app_context():
        assert db.session.get(Customer, customer_id).name == "العميل المحدث"

    response = client.post(
        f"/admin/customers/{customer_id}",
        data={
            "action": "address",
            "recipient_name": "المستلم",
            "address_phone": "967700000001",
            "district": "وسط المدينة",
            "street": "شارع 1",
            "landmark": "قرب السوق",
        },
    )
    assert response.status_code == 200

    with app.app_context():
        address = CustomerAddress.query.filter_by(customer_id=customer_id).first()
        assert address is not None
        assert address.recipient_name == "المستلم"


def test_storefront_admin_builder(client, app):
    with app.app_context():
        currency = Currency(code="USD", name_ar="دولار", is_base=True)
        db.session.add(currency)
        db.session.flush()
        product = Product(
            sku="TEST-SKU-001",
            name="منتج تجريبي",
            slug="test-product-001",
            base_currency_id=currency.id,
            base_price=10,
            status="published",
        )
        db.session.add(product)
        db.session.flush()
        page = StorefrontPage(code="home-test", name="الرئيسية", route="/home-test")
        db.session.add(page)
        db.session.flush()
        section = StorefrontSection(page_id=page.id, section_type="product_grid", title="منتجات")
        db.session.add(section)
        db.session.commit()
        page_id, section_id, product_id = page.id, section.id, product.id

    with client.session_transaction() as session:
        session["admin_id"] = 1

    response = client.get("/admin/storefront/pages")
    assert response.status_code == 200
    assert "home-test" in response.get_data(as_text=True)

    response = client.post(
        "/admin/storefront/sections/{}/items".format(section_id),
        data={"item_type": "product", "item_id": str(product_id), "custom_label": "مميز"},
    )
    assert response.status_code == 302

    with app.app_context():
        row = StorefrontSectionItem.query.filter_by(section_id=section_id).first()
        assert row is not None
        assert row.item_type == "product"
        assert row.item_id == product_id

    response = client.post(
        "/admin/storefront/pages",
        data={"action": "page_create", "code": "offers-test", "name": "العروض", "route": "/offers-test"},
    )
    assert response.status_code == 302

    with app.app_context():
        assert StorefrontPage.query.filter_by(code="offers-test").first() is not None


def test_catalog_options_forms_and_quick_references(client, app):
    with client.session_transaction() as session:
        session["admin_id"] = 1

    response = client.post(
        "/admin/options",
        data={
            "action": "color_create",
            "name": "أسود",
            "hex_code": "#111111",
            "sort_order": "1",
        },
        follow_redirects=False,
    )
    assert response.status_code == 200

    with app.app_context():
        color = Color.query.filter_by(name="أسود").first()
        assert color is not None
        color_id = color.id

    response = client.post(
        "/admin/options",
        data={
            "action": "size_create",
            "group": "EU",
            "code": "M",
            "label": "متوسط",
            "sort_order": "1",
        },
        follow_redirects=False,
    )
    assert response.status_code == 200

    response = client.post(
        "/api/v1/catalog/reference/colors",
        json={"name": "أحمر", "hex_code": "#ef4444", "sort_order": 2},
    )
    assert response.status_code == 201
    assert response.get_json()["item"]["name"] == "أحمر"

    response = client.post(
        "/api/v1/catalog/badges",
        json={
            "name": "جديد",
            "code": "new",
            "bg_color": "#111827",
            "text_color": "#ffffff",
            "style": "solid",
            "priority": 10,
        },
    )
    assert response.status_code == 201
    assert response.get_json()["item"]["code"] == "new"


def test_product_wizard_media_snapshot_exposes_color_data(client, app):
    with app.app_context():
        currency = Currency(code="SAR", name_ar="ريال", is_base=True)
        color = Color(name="أبيض", hex_code="#ffffff")
        db.session.add_all([currency, color])
        db.session.flush()
        product = Product(
            sku="WIZARD-MEDIA-001",
            name="منتج صور",
            slug="wizard-media-001",
            base_currency_id=currency.id,
            base_price=100,
            status="draft",
        )
        db.session.add(product)
        db.session.flush()
        asset = MediaAsset(
            storage_key="products/test/asset.webp",
            url="/media/products/test/asset.webp",
            mime_type="image/webp",
            width=800,
            height=800,
            size_bytes=1000,
        )
        db.session.add(asset)
        db.session.flush()
        media = ProductMedia(product_id=product.id, asset_id=asset.id, color_id=color.id, role="gallery")
        db.session.add(media)
        db.session.commit()
        product_id = product.id

    response = client.get(f"/api/v1/catalog/products/{product_id}/wizard")
    assert response.status_code == 200
    item = response.get_json()["item"]
    media = item["media"][0]
    assert media["url"] == "/media/products/test/asset.webp"
    assert media["color_id"] == color_id
    assert media["color_name"] == "أبيض"
