def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()['ok'] is True


def test_admin_dashboard_renders(client):
    response = client.get("/admin/")
    assert response.status_code == 200
    assert 'لوحة الإدارة' in response.get_data(as_text=True)


def test_module_blueprints_are_registered(client):
    expected = {
        "/api/v1/catalog/categories": 200,
        "/api/v1/pricing/groups": 200,
        "/api/v1/customer/auth/request-otp": 201,
        "/api/v1/system/health": 200,
        "/api/v1/geo/countries": 200,
        "/api/v1/storefront/pages": 200,
        "/api/v1/commerce/orders": 200,
        "/api/v1/support/conversations": 200,
        "/api/v1/promotions/campaigns": 200,
        "/api/v1/after_sales/reviews/product/1": 404,
        "/api/v1/notifications/notifications/1": 200,
        "/api/v1/reports/sales": 200,
        "/api/v1/search/products": 200,
    }
    for path, status in expected.items():
        assert client.get(path).status_code == status, path
