from . import api_bp
from ...models import AppSetting, FeatureFlag, Theme, ThemeToken


@api_bp.get("/health")
def health():
    return {"ok": True, "module": "system"}


@api_bp.get("/features")
def features():
    rows = FeatureFlag.query.filter_by(is_active=True).order_by(FeatureFlag.key).all()
    return {"items": [{"key": x.key, "enabled": x.enabled, "conditions": x.conditions} for x in rows]}


@api_bp.get("/theme/<string:code>")
def theme(code):
    theme = Theme.query.filter_by(code=code, is_active=True).first()
    if theme is None:
        return {"error": "not_found"}, 404
    tokens = ThemeToken.query.filter_by(theme_id=theme.id).order_by(ThemeToken.token_name).all()
    return {"theme": {"id": theme.id, "code": theme.code, "name": theme.name}, "tokens": [{"name": x.token_name, "value": x.value, "type": x.value_type} for x in tokens]}


@api_bp.get("/settings")
def settings():
    rows = AppSetting.query.order_by(AppSetting.group_code, AppSetting.key).all()
    return {"items": [{"group": x.group_code, "key": x.key, "value": x.value, "type": x.value_type} for x in rows]}
