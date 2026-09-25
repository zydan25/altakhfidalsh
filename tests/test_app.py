from app import create_app


def test_health_endpoint():
    app = create_app()
    client = app.test_client()

    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json()["ok"] is True


def test_admin_dashboard_renders_without_database_records():
    app = create_app()
    client = app.test_client()

    response = client.get("/admin/")

    assert response.status_code == 200
    assert "لوحة الإدارة" in response.get_data(as_text=True)
