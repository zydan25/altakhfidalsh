import hashlib
from functools import wraps

from flask import g, request

from ...extensions import db
from ...models import AuthSession, Customer


def _hash_token(token):
    return hashlib.sha256(token.encode()).hexdigest()


def current_customer():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:].strip()
    if not token:
        return None
    session = (
        AuthSession.query
        .filter_by(access_token_hash=_hash_token(token))
        .first()
    )
    if session is None or session.revoked_at is not None:
        return None
    from datetime import datetime, timezone
    if session.expires_at <= datetime.now(timezone.utc):
        session.revoked_at = db.func.now()
        db.session.commit()
        return None
    customer = db.session.get(Customer, session.customer_id)
    g.customer = customer
    return customer


def customer_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        customer = current_customer()
        if customer is None:
            return {"error": "unauthorized"}, 401
        return view(*args, **kwargs)
    return wrapped
