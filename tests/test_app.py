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
        "/api/v1/customer/auth/request-otp": None,
        "/api/v1/system/health": 200,
        "/api/v1/geo/countries": 200,
        "/api/v1/storefront/pages": 200,
        "/api/v1/commerce/orders": 200,
        "/api/v1/support/conversations": 401,
        "/api/v1/promotions/campaigns": 200,
        "/api/v1/after_sales/reviews/product/1": 200,
        "/api/v1/notifications/notifications/1": 401,
        "/api/v1/reports/sales": 200,
        "/api/v1/search/products": 200,
    }
    for path, status in expected.items():
        if status is None:
            response = client.post(path, json={"phone": "771234567"})
        else:
            response = client.get(path)
        assert response.status_code == status or (path.endswith("/request-otp") and response.status_code == 201), path


def test_admin_navigation_routes_have_explicit_permissions():
    from app.admin.navigation import NAVIGATION
    from app.admin.security import permission_code

    routes = [
        item.route
        for section in NAVIGATION
        for item in section.children
    ]

    assert routes
    missing = [route for route in routes if permission_code(route, "GET") is None]
    assert missing == []


def test_unknown_admin_route_fails_closed_to_system_permission():
    from app.admin.security import permission_code

    assert permission_code("/admin/future-module", "GET") == "system.manage"
    assert permission_code("/admin/future-module", "POST") == "system.manage"
    assert permission_code("/public/future-module", "GET") is None


def test_admin_service_worker_does_not_cache_authenticated_html(client):
    response = client.get("/admin/static/sw.js")
    assert response.status_code == 200
    body = response.get_data(as_text=True)
    assert 'altakhfidalsh-admin-v5' in body
    assert 'event.respondWith(fetch(event.request));' in body
    admin_handler = body.split('// Authenticated admin HTML is intentionally never persisted in the cache.', 1)[1]
    assert 'caches.open(CACHE).then(cache => cache.put(event.request, copy));' not in admin_handler
