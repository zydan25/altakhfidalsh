from flask import request

from . import api_bp
from ...security import admin_api_required
from .services import SystemService
from ...extensions import db
from ...models import Admin, AppSetting, FeatureFlag, Role, Theme, ThemeToken, ShippingPolicy, ReturnPolicy, WarrantyPolicy


@api_bp.get("/policies")
def policies():
    privacy=AppSetting.query.filter_by(group_code="storefront",key="privacy_policy").first()
    shipping=ShippingPolicy.query.filter_by(is_active=True).order_by(ShippingPolicy.id.desc()).first()
    returns=ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.id.desc()).first()
    warranty=WarrantyPolicy.query.filter_by(is_active=True).order_by(WarrantyPolicy.id.desc()).first()
    return {"item":{"privacy":privacy.value if privacy and privacy.value else "نحترم خصوصيتك ونستخدم بياناتك لتشغيل الطلبات وخدمة العملاء وتحسين تجربة المتجر.","shipping":{"name":shipping.name,"free_shipping_enabled":bool(shipping.free_shipping_enabled),"min_order_amount":str(shipping.min_order_amount) if shipping.min_order_amount is not None else None,"promo_text":shipping.promo_text,"delivery_window":shipping.delivery_window} if shipping else None,"returns":{"name":returns.name,"return_window_days":returns.return_window_days,"conditions":returns.conditions,"fee_rule":returns.fee_rule,"refund_method":returns.refund_method} if returns else None,"warranty":{"name":warranty.name,"duration_days":warranty.duration_days,"coverage":warranty.coverage,"exclusions":warranty.exclusions,"claim_method":warranty.claim_method} if warranty else None}}

@api_bp.get("/health")
def health():
    return {"ok": True, "module": "system"}


@api_bp.get("/permissions")
def permissions():
    return {"items": SystemService.list_permissions()}


@api_bp.post("/permissions")
@admin_api_required("system.manage")
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
@admin_api_required("system.manage")
def create_role():
    try:
        return {"item": SystemService.create_role(request.get_json(silent=True) or {})}, 201
    except (KeyError, ValueError) as exc:
        return {"error": "role_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/admins/<int:admin_id>/roles/<int:role_id>")
@admin_api_required("system.manage")
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
@admin_api_required("system.manage")
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


@api_bp.get("/policies")
def public_policies():
    from ...models import ReturnPolicy
    privacy_row = AppSetting.query.filter_by(group_code="storefront", key="privacy_policy").first()
    privacy = privacy_row.value if privacy_row and privacy_row.value else (
        "نلتزم بحماية بياناتك واستخدامها فقط لتقديم خدمات المتجر والطلب والتوصيل والدعم، "
        "ونحتفظ بالبيانات اللازمة لإدارة الحسابات والطلبات وفق الأنظمة المعمول بها."
    )
    policy = ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.id).first()
    return {
        "privacy": {"title": "سياسة الخصوصية", "body": privacy},
        "return": {
            "title": policy.name if policy else "سياسة الإرجاع والاسترداد",
            "body": (
                "\n".join(
                    part for part in [
                        policy.conditions if policy else None,
                        (f"مدة الإرجاع: {policy.return_window_days} يومًا" if policy and policy.return_window_days else None),
                        (f"الرسوم: {policy.fee_rule}" if policy and policy.fee_rule else None),
                        (f"الاسترداد: {policy.refund_method}" if policy and policy.refund_method else None),
                    ] if part
                )
                if policy else "تطبق سياسة الإرجاع والاسترداد المعتمدة في المتجر."
            ),
        },
    }


@api_bp.get("/theme/<string:code>")
def theme(code):
    theme = Theme.query.filter_by(code=code, is_active=True).first()
    if theme is None:
        return {"error": "not_found"}, 404
    tokens = ThemeToken.query.filter_by(theme_id=theme.id).order_by(ThemeToken.token_name).all()
    return {"theme": {"id": theme.id, "code": theme.code, "name": theme.name}, "tokens": [{"name": x.token_name, "value": x.value, "type": x.value_type} for x in tokens]}


@api_bp.post("/theme/<string:code>/tokens")
@admin_api_required("theme.manage")
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
