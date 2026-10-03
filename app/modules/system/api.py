from flask import request

from . import api_bp
from ...security import admin_api_required
from .services import SystemService
from ...extensions import db
from ...models import Admin, AppSetting, FeatureFlag, Role, Theme, ThemeToken, ShippingPolicy, ReturnPolicy, WarrantyPolicy


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
