from flask import request

from . import api_bp
from .services import SystemService
from ...extensions import db
from ...models import Admin, AppSetting, FeatureFlag, Role, Theme, ThemeToken


@api_bp.get("/health")
def health():
    return {"ok": True, "module": "system"}


@api_bp.get("/permissions")
def permissions():
    return {"items": SystemService.list_permissions()}


@api_bp.post("/permissions")
def create_permission():
    try:
        return {"item": SystemService.create_permission(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "permission_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/roles")
def roles():
    rows = Role.query.filter_by(is_active=True).order_by(Role.name).all()
    return {"items": [{"id": x.id, "name": x.name, "code": x.code} for x in rows]}


@api_bp.post("/roles")
def create_role():
    try:
        return {"item": SystemService.create_role(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "role_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/admins/<int:admin_id>/roles/<int:role_id>")
def assign_role(admin_id, role_id):
    try:
        return {"item": SystemService.assign_role(admin_id, role_id)}
    except LookupError as exc:
        return {"error": "role_assignment_failed", "detail": str(exc)}, 404


@api_bp.get("/admins")
def admins():
    rows = Admin.query.filter_by(is_active=True).order_by(Admin.username).all()
    return {"items": [{"id": x.id, "username": x.username, "phone": x.phone, "email": x.email, "status": x.status} for x in rows]}


@api_bp.get("/audit-logs")
def audit_logs():
    return {"items": SystemService.audit_logs(request.args.get("limit", 100, type=int))}


@api_bp.get("/features")
def features():
    rows = FeatureFlag.query.filter_by(is_active=True).order_by(FeatureFlag.key).all()
    return {"items": [{"key": x.key, "enabled": x.enabled, "conditions": x.conditions} for x in rows]}


@api_bp.patch("/features/<string:key>")
def update_feature(key):
    payload = request.get_json(silent=True) or {}
    row = FeatureFlag.query.filter_by(key=key).first()
    if row is None:
        row = FeatureFlag(key=key, enabled=bool(payload.get("enabled", False)), conditions=payload.get("conditions") or {})
        db.session.add(row)
    else:
        if "enabled" in payload:
            row.enabled = bool(payload["enabled"])
        if "conditions" in payload:
            row.conditions = payload["conditions"] or {}
    db.session.commit()
    return {"item": {"key": row.key, "enabled": row.enabled, "conditions": row.conditions}}


@api_bp.get("/theme/<string:code>")
def theme(code):
    theme = Theme.query.filter_by(code=code, is_active=True).first()
    if theme is None:
        return {"error": "not_found"}, 404
    tokens = ThemeToken.query.filter_by(theme_id=theme.id).order_by(ThemeToken.token_name).all()
    return {"theme": {"id": theme.id, "code": theme.code, "name": theme.name}, "tokens": [{"name": x.token_name, "value": x.value, "type": x.value_type} for x in tokens]}


@api_bp.post("/theme/<string:code>/tokens")
def upsert_theme_token(code):
    payload = request.get_json(silent=True) or {}
    theme = Theme.query.filter_by(code=code, is_active=True).first()
    if theme is None:
        return {"error": "theme_not_found"}, 404
    name = str(payload["name"]).strip()
    token = ThemeToken.query.filter_by(theme_id=theme.id, token_name=name).first()
    if token is None:
        token = ThemeToken(theme_id=theme.id, token_name=name, value=str(payload["value"]), value_type=str(payload.get("type", "text")))
        db.session.add(token)
    else:
        token.value = str(payload["value"])
        token.value_type = str(payload.get("type", token.value_type))
    db.session.commit()
    return {"item": {"name": token.token_name, "value": token.value, "type": token.value_type}}
