from ...extensions import db
from ...models import (
    Admin,
    AdminRole,
    AuditLog,
    Permission,
    Role,
    RolePermission,
)


class SystemService:
    @staticmethod
    def list_permissions():
        return [
            {"id": x.id, "code": x.code, "name": x.name}
            for x in Permission.query.filter_by(is_active=True).order_by(Permission.code).all()
        ]

    @staticmethod
    def create_permission(payload):
        code = str(payload["code"]).strip()
        name = str(payload["name"]).strip()
        if Permission.query.filter_by(code=code).first():
            raise ValueError("permission code already exists")
        row = Permission(code=code, name=name)
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "code": row.code, "name": row.name}

    @staticmethod
    def create_role(payload):
        code = str(payload["code"]).strip()
        name = str(payload["name"]).strip()
        if Role.query.filter_by(code=code).first():
            raise ValueError("role code already exists")
        role = Role(name=name, code=code)
        db.session.add(role)
        db.session.flush()
        for permission_id in payload.get("permission_ids", []):
            if db.session.get(Permission, int(permission_id)) is None:
                raise ValueError("permission not found")
            db.session.add(RolePermission(role_id=role.id, permission_id=int(permission_id)))
        db.session.commit()
        return {"id": role.id, "name": role.name, "code": role.code}

    @staticmethod
    def assign_role(admin_id, role_id):
        if db.session.get(Admin, admin_id) is None or db.session.get(Role, role_id) is None:
            raise LookupError("admin or role not found")
        existing = AdminRole.query.filter_by(admin_id=admin_id, role_id=role_id).first()
        if existing is None:
            db.session.add(AdminRole(admin_id=admin_id, role_id=role_id))
            db.session.commit()
        return {"admin_id": admin_id, "role_id": role_id}

    @staticmethod
    def audit_logs(limit=100):
        rows = AuditLog.query.order_by(AuditLog.id.desc()).limit(min(max(limit, 1), 500)).all()
        return [
            {
                "id": x.id,
                "admin_id": x.admin_id,
                "action": x.action,
                "entity_type": x.entity_type,
                "entity_id": x.entity_id,
                "before": x.before_json,
                "after": x.after_json,
                "request_id": x.request_id,
                "created_at": x.created_at.isoformat(),
            }
            for x in rows
        ]
