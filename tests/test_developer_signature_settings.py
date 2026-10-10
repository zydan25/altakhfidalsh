from app.extensions import db
from app.models import AppSetting


STYLE_KEY = "developer_signature_style"
ENABLED_KEY = "developer_signature_enabled"


def test_developer_signature_defaults_to_always_visible_minimal_style(client):
    response = client.get("/api/v1/system/store-info")

    assert response.status_code == 200
    item = response.get_json()["item"]
    assert item[STYLE_KEY] == "minimal"
    assert ENABLED_KEY not in item


def test_admin_can_select_each_supported_signature_design_without_hide_toggle(client):
    for style in ("minimal", "signature", "royal", "atelier"):
        response = client.post(
            "/admin/system/settings",
            data={
                "action": "save_developer_signature_settings",
                "style": style,
            },
        )
        assert response.status_code == 200
        item = client.get("/api/v1/system/store-info").get_json()["item"]
        assert item[STYLE_KEY] == style
        assert ENABLED_KEY not in item

    enabled_setting = AppSetting.query.filter_by(
        group_code="storefront", key=ENABLED_KEY
    ).first()
    style_setting = AppSetting.query.filter_by(
        group_code="storefront", key=STYLE_KEY
    ).first()
    assert enabled_setting is None
    assert style_setting is not None
    assert style_setting.value == "atelier"


def test_legacy_signature_hide_flag_is_removed_when_saving_style(client):
    db.session.add(AppSetting(
        group_code="storefront",
        key=ENABLED_KEY,
        value="false",
        value_type="boolean",
    ))
    db.session.commit()

    response = client.post(
        "/admin/system/settings",
        data={
            "action": "save_developer_signature_settings",
            "style": "royal",
        },
    )
    assert response.status_code == 200
    assert AppSetting.query.filter_by(
        group_code="storefront", key=ENABLED_KEY
    ).first() is None
    item = client.get("/api/v1/system/store-info").get_json()["item"]
    assert item[STYLE_KEY] == "royal"
    assert ENABLED_KEY not in item


def test_invalid_signature_style_falls_back_to_minimal(client):
    db.session.add(AppSetting(
        group_code="storefront",
        key=STYLE_KEY,
        value="not-a-style",
        value_type="text",
    ))
    db.session.commit()

    response = client.get("/api/v1/system/store-info")

    assert response.status_code == 200
    assert response.get_json()["item"][STYLE_KEY] == "minimal"
