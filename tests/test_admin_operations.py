from app.extensions import db
from app.models import Customer, CustomerAddress, StorefrontPage, StorefrontSection, StorefrontSectionItem


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
        page = StorefrontPage(code="home-test", name="الرئيسية", route="/home-test")
        db.session.add(page)
        db.session.flush()
        section = StorefrontSection(page_id=page.id, section_type="product_grid", title="منتجات")
        db.session.add(section)
        db.session.commit()
        page_id, section_id = page.id, section.id

    with client.session_transaction() as session:
        session["admin_id"] = 1

    response = client.get("/admin/storefront/pages")
    assert response.status_code == 200
    assert "home-test" in response.get_data(as_text=True)

    response = client.post(
        "/admin/storefront/sections/{}/items".format(section_id),
        data={"item_type": "product", "item_id": "1", "custom_label": "مميز"},
    )
    assert response.status_code == 302

    with app.app_context():
        row = StorefrontSectionItem.query.filter_by(section_id=section_id).first()
        assert row is not None
        assert row.item_type == "product"
        assert row.item_id == 1

    response = client.post(
        "/admin/storefront/pages",
        data={"code": "offers-test", "name": "العروض", "route": "/offers-test"},
    )
    assert response.status_code == 302

    with app.app_context():
        assert StorefrontPage.query.filter_by(code="offers-test").first() is not None
