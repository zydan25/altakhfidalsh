def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()['ok'] is True


def test_admin_dashboard_renders(client):
    response = client.get("/admin/")
    assert response.status_code == 200
    assert 'لوحة الإدارة' in response.get_data(as_text=True)


def test_module_blueprints_are_registered(client):
    assert client.get("/api/v1/system/health").status_code == 200
    assert client.get("/api/v1/geo/countries").status_code == 200
    assert client.get("/api/v1/catalog/categories").status_code == 200