from app.extensions import db
from app.models import AppSetting


SETTING_KEY = "account_order_status_section_enabled"


def test_account_order_status_section_setting_defaults_to_visible(client):
    response = client.get("/api/v1/system/store-info")

    assert response.status_code == 200
    assert response.get_json()["item"][SETTING_KEY] is True


def test_admin_can_hide_and_restore_account_order_status_section(client):
    hidden = client.post(
        "/admin/system/settings",
        data={"action": "save_account_order_status_section"},
    )
    assert hidden.status_code == 200

    response = client.get("/api/v1/system/store-info")
    assert response.status_code == 200
    assert response.get_json()["item"][SETTING_KEY] is False

    enabled = client.post(
        "/admin/system/settings",
        data={"action": "save_account_order_status_section", "enabled": "on"},
    )
    assert enabled.status_code == 200

    response = client.get("/api/v1/system/store-info")
    assert response.get_json()["item"][SETTING_KEY] is True

    row = AppSetting.query.filter_by(
        group_code="storefront",
        key=SETTING_KEY,
    ).first()
    assert row is not None
    assert row.value == "true"
    assert row.value_type == "boolean"
