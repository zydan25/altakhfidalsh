from functools import wraps

from flask import current_app, session


def _has_permission(code):
    if current_app.config.get("ADMIN_DEV_BYPASS", False):
        return True
    admin_id = session.get("admin_id")
    if not admin_id:
        return False

    from ..extensions import db
    from ..models import AdminRole, Permission, RolePermission

    row = (
        db.session.query(Permission.id)
        .join(RolePermission, RolePermission.permission_id == Permission.id)
        .join(AdminRole, AdminRole.role_id == RolePermission.role_id)
        .filter(
            AdminRole.admin_id == admin_id,
            Permission.code == code,
        )
        .first()
    )
    return row is not None


def admin_api_required(permission):
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not session.get("admin_id") and not current_app.config.get("ADMIN_DEV_BYPASS", False):
                return {"error": "unauthorized"}, 401
            if permission and not _has_permission(permission):
                return {"error": "forbidden", "permission": permission}, 403
            return view(*args, **kwargs)
        return wrapped
    return decorator
