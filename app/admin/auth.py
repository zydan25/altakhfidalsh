from datetime import datetime, timezone
from functools import wraps

from flask import current_app, redirect, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

from ..extensions import db
from ..models import Admin


class AdminAuthService:
    @staticmethod
    def login(username, password):
        admin = Admin.query.filter_by(username=username, is_active=True).first()
        if admin is None or not admin.password_hash or not check_password_hash(admin.password_hash, password):
            raise ValueError("invalid credentials")
        admin.last_login = datetime.now(timezone.utc)
        db.session.commit()
        session.clear()
        session["admin_id"] = admin.id
        session["admin_username"] = admin.username
        return {"id": admin.id, "username": admin.username}

    @staticmethod
    def logout():
        session.clear()

    @staticmethod
    def bootstrap(username, password):
        if not username or not password or len(password) < 8:
            raise ValueError("username and password (8+ chars) are required")
        admin = Admin.query.filter_by(username=username).first()
        if admin is None:
            admin = Admin(username=username, status="active")
            db.session.add(admin)
        admin.password_hash = generate_password_hash(password)
        admin.is_active = True
        db.session.commit()
        return {"id": admin.id, "username": admin.username}


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        bypass = current_app.config.get("ADMIN_DEV_BYPASS", False)
        if bypass:
            return view(*args, **kwargs)
        if not session.get("admin_id"):
            return redirect(url_for("admin.login", next=request.path))
        return view(*args, **kwargs)

    return wrapped
