from flask import current_app, request, session


ROUTE_PERMISSIONS = {
    "GET": {
        "/admin/": "dashboard.view",
        "/admin/tasks": "order.manage",
        "/admin/products": "product.view",
        "/admin/products/new": "product.create",
        "/admin/products/drafts": "product.view",
        "/admin/categories": "category.view",
        "/admin/category-strip": "content.manage",
        "/admin/brands": "product.view",
        "/admin/options": "product.view",
        "/admin/inventory": "inventory.manage",
        "/admin/media": "product.view",
        "/admin/product-settings": "product.edit",
        "/admin/catalog/policies": "policy.manage",
        "/admin/banners": "content.view",
        "/admin/banner-targets": "content.manage",
        "/admin/category-circles": "content.view",
        "/admin/side-categories": "side_category.view",
        "/admin/trends": "hashtag.view",
        "/admin/hashtags": "hashtag.view",
        "/admin/campaigns": "campaign.view",
        "/admin/storefront/pages": "content.manage",
        "/admin/storefront/sections": "content.manage",
        "/admin/storefront/collections": "content.manage",
        "/admin/pricing/groups": "pricing.view",
        "/admin/pricing/currencies": "pricing.view",
        "/admin/pricing/rates": "pricing.view",
        "/admin/geo": "geo.manage",
        "/admin/pricing/city-assignments": "pricing.view",
        "/admin/pricing/customer-assignments": "pricing.view",
        "/admin/pricing/preview": "pricing.view",
        "/admin/orders": "order.view",
        "/admin/payments": "payment.manage",
        "/admin/payments/proofs": "payment.manage",
        "/admin/shipping": "shipping.manage",
        "/admin/returns": "refund.approve",
        "/admin/warranty": "policy.manage",
        "/admin/reviews": "content.manage",
        "/admin/customers": "customer.view",
        "/admin/customers/addresses": "customer.view",
        "/admin/chat": "customer.view",
        "/admin/notifications": "customer.view",
        "/admin/attachments": "customer.view",
        "/admin/promotions/coupons": "promotion.manage",
        "/admin/promotions/gifts": "promotion.manage",
        "/admin/finance/wallets": "wallet.adjust",
        "/admin/finance/wallet-ledger": "wallet.adjust",
        "/admin/reports": "report.view",
        "/admin/whatsapp": "system.manage",
        "/admin/system/admins": "system.manage",
        "/admin/system/roles": "system.manage",
        "/admin/system/audit": "system.manage",
        "/admin/system/theme": "theme.manage",
        "/admin/system/settings": "system.manage",
        "/admin/system/features": "system.manage",
    },
    "POST": {
        "/admin/products": "product.create",
        "/admin/products/new": "product.create",
        "/admin/categories": "category.manage",
        "/admin/category-strip": "content.manage",
        "/admin/side-categories": "side_category.manage",
        "/admin/brands": "product.edit",
        "/admin/options": "product.edit",
        "/admin/catalog/policies": "policy.manage",
        "/admin/banners": "banner.manage",
        "/admin/banner-targets": "content.manage",
        "/admin/trends": "hashtag.manage",
        "/admin/hashtags": "hashtag.manage",
        "/admin/campaigns": "campaign.manage",
        "/admin/storefront/pages": "content.manage",
        "/admin/storefront/sections": "content.manage",
        "/admin/storefront/collections": "content.manage",
        "/admin/pricing/groups": "pricing.manage",
        "/admin/pricing/currencies": "pricing.manage",
        "/admin/pricing/rates": "pricing.manage",
        "/admin/geo": "geo.manage",
        "/admin/pricing/city-assignments": "pricing.manage",
        "/admin/pricing/customer-assignments": "pricing.manage",
        "/admin/orders": "order.manage",
        "/admin/payments": "payment.manage",
        "/admin/payments/proofs": "payment.manage",
        "/admin/shipping": "shipping.manage",
        "/admin/returns": "refund.approve",
        "/admin/warranty": "policy.manage",
        "/admin/reviews": "content.manage",
        "/admin/customers": "customer.manage",
        "/admin/customers/addresses": "customer.manage",
        "/admin/chat": "customer.manage",
        "/admin/notifications": "customer.manage",
        "/admin/attachments": "customer.manage",
        "/admin/promotions/coupons": "promotion.manage",
        "/admin/promotions/gifts": "promotion.manage",
        "/admin/finance/wallets": "wallet.adjust",
        "/admin/finance/wallet-ledger": "wallet.adjust",
        "/admin/whatsapp": "system.manage",
        "/admin/system/admins": "system.manage",
        "/admin/system/roles": "system.manage",
        "/admin/system/audit": "system.manage",
        "/admin/system/theme": "theme.manage",
        "/admin/system/settings": "system.manage",
        "/admin/system/features": "system.manage",
    },
}


def permission_code(path, method):
    exact = ROUTE_PERMISSIONS.get(method, {})
    if path in exact:
        return exact[path]

    prefix_permissions = (
        ("/admin/products/", "product.edit"),
        ("/admin/orders/", "order.manage"),
        ("/admin/customers/", "customer.manage"),
        ("/admin/pricing/", "pricing.manage"),
        ("/admin/promotions/", "promotion.manage"),
        ("/admin/finance/", "wallet.adjust"),
        ("/admin/system/", "system.manage"),
        ("/admin/storefront/", "content.manage"),
        ("/admin/catalog/", "policy.manage"),
    )
    for prefix, code in prefix_permissions:
        if path.startswith(prefix):
            if method == "GET" and prefix == "/admin/pricing/":
                return "pricing.view"
            if method == "GET" and prefix == "/admin/products/":
                return "product.edit" if path.rstrip("/").endswith("/edit") else "product.view"
            if method == "GET" and prefix == "/admin/orders/":
                return "order.view"
            if method == "GET" and prefix == "/admin/customers/":
                return "customer.view"
            return code

    if path.startswith("/admin/"):
        # Fail closed for future admin routes until an explicit permission is assigned.
        return "system.manage"
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
