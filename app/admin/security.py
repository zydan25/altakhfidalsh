from flask import current_app, request, session


ROUTE_PERMISSIONS = {
    "GET": {
        "/admin/": "dashboard.view",
        "/admin/products": "product.view",
        "/admin/categories": "category.view",
        "/admin/pricing/groups": "pricing.view",
        "/admin/pricing/preview": "pricing.view",
        "/admin/banners": "content.view",
        "/admin/campaigns": "campaign.view",
        "/admin/hashtags": "hashtag.view",
        "/admin/payments": "payment.manage",
        "/admin/payments/proofs": "payment.manage",
        "/admin/shipping": "shipping.manage",
        "/admin/returns": "refund.approve",
        "/admin/warranty": "policy.manage",
        "/admin/reviews": "content.manage",
        "/admin/chat": "customer.view",
        "/admin/customers": "customer.view",
        "/admin/storefront/pages": "content.manage",
        "/admin/storefront/sections": "content.manage",
    },
    "POST": {
        "/admin/products": "product.create",
        "/admin/products/new": "product.create",
        "/admin/categories": "category.manage",
        "/admin/pricing/groups": "pricing.manage",
        "/admin/banners": "banner.manage",
        "/admin/campaigns": "campaign.manage",
        "/admin/hashtags": "hashtag.manage",
    },
}


def permission_code(path, method):
    exact = ROUTE_PERMISSIONS.get(method, {})
    if path in exact:
        return exact[path]
    if path.startswith("/admin/products/"):
        return "product.edit" if method in {"PATCH", "PUT", "POST"} else "product.view"
    if path.startswith("/admin/orders"):
        return "order.manage" if method != "GET" else "order.view"
    if path.startswith("/admin/customers"):
        return "customer.manage" if method != "GET" else "customer.view"
    return None


def can_access(code):
    if not code:
        return True
    if current_app.config.get("ADMIN_DEV_BYPASS", False):
        return True
    admin_id = session.get("admin_id")
    if not admin_id:
        return False

    from ..models import AdminRole, Permission, RolePermission
    from ..extensions import db

    permission = (
        db.session.query(Permission.id)
        .join(RolePermission, RolePermission.permission_id == Permission.id)
        .join(AdminRole, AdminRole.role_id == RolePermission.role_id)
        .filter(AdminRole.admin_id == admin_id, Permission.code == code)
        .first()
    )
    return permission is not None


def init_admin_security(admin_bp):
    @admin_bp.before_request
    def protect():
        endpoint = request.endpoint or ""
        if endpoint in {"admin.login", "admin.logout", "admin.static"}:
            return None
        code = permission_code(request.path, request.method)
        if not session.get("admin_id") and not current_app.config.get("ADMIN_DEV_BYPASS", False):
            from flask import redirect, url_for
            return redirect(url_for("admin.login", next=request.path))
        if code and not can_access(code):
            return {"error": "forbidden", "permission": code}, 403
        return None
