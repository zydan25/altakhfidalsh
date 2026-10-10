from app.models import AppSetting


ENABLED_KEY = "developer_signature_enabled"
STYLE_KEY = "developer_signature_style"


def test_developer_signature_defaults_to_existing_enabled_classic_style(client):
    response = client.get("/api/v1/system/store-info")

    assert response.status_code == 200
    item = response.get_json()["item"]
    assert item[ENABLED_KEY] is True
    assert item[STYLE_KEY] == "classic"


def test_admin_can_disable_and_select_each_supported_signature_design(client):
    for style in ("classic", "modern", "premium"):
        response = client.post(
            "/admin/system/settings",
            data={
                "action": "save_developer_signature_settings",
                "enabled": "on",
                "style": style,
            },
        )
        assert response.status_code == 200
        item = client.get("/api/v1/system/store-info").get_json()["item"]
        assert item[ENABLED_KEY] is True
        assert item[STYLE_KEY] == style

    response = client.post(
        "/admin/system/settings",
        data={
            "action": "save_developer_signature_settings",
            "style": "premium",
        },
    )
    assert response.status_code == 200
    item = client.get("/api/v1/system/store-info").get_json()["item"]
    assert item[ENABLED_KEY] is False
    assert item[STYLE_KEY] == "premium"

    enabled_setting = AppSetting.query.filter_by(
        group_code="storefront", key=ENABLED_KEY
    ).first()
    style_setting = AppSetting.query.filter_by(
        group_code="storefront", key=STYLE_KEY
    ).first()
    assert enabled_setting is not None
    assert enabled_setting.value == "false"
    assert enabled_setting.value_type == "boolean"
    assert style_setting is not None
    assert style_setting.value == "premium"


def test_invalid_signature_style_is_not_returned_to_client(client):
    from app.extensions import db

    db.session.add(
        AppSetting(
            group_code="storefront",
            key=STYLE_KEY,
            value="not-a-style",
            value_type="text",
        )
    )
    db.session.commit()

    response = client.get("/api/v1/system/store-info")

    assert response.status_code == 200
    assert response.get_json()["item"][STYLE_KEY] == "classic"
