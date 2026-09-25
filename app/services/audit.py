import json

from ..extensions import db
from ..models import AuditLog


class AuditService:
    @staticmethod
    def record(
        *,
        action,
        entity_type,
        entity_id=None,
        admin_id=None,
        before=None,
        after=None,
        request_id=None,
        ip_address=None,
    ):
        log = AuditLog(
            admin_id=admin_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            before_json=json.loads(json.dumps(before, default=str)) if before is not None else None,
            after_json=json.loads(json.dumps(after, default=str)) if after is not None else None,
            request_id=request_id,
            ip_address=ip_address,
        )
        db.session.add(log)
        return log
