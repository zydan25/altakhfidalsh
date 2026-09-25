from sqlalchemy import func

from flask import request

from ..extensions import db
from ..models import Conversation, Notification, Order
from .navigation import NAVIGATION, NavItem, NavSection


def build_admin_context():
    current_path = request.path
    sections = []
    page_item_map = []

    for source in NAVIGATION:
        children = [
            NavItem(
                label=item.label,
                route=item.route,
                icon=item.icon,
                badge_key=item.badge_key,
            )
            for item in source.children
        ]
        active = any(
            current_path == child.route
            or current_path.startswith(child.route + "/")
            for child in children
        )
        sections.append(
            NavSection(
                label=source.label,
                icon=source.icon,
                children=children,
                active=active,
            )
        )
        for child in children:
            page_item_map.append(
                {"label": child.label, "route": child.route, "section": source.label}
            )

    theme_values = {}
    try:
        from ..models import AppSetting
        for row in AppSetting.query.filter_by(group_code="theme").all():
            theme_values[row.key] = row.value
    except Exception:
        db.session.rollback()

    css_vars = "; ".join(
        f"--{key.replace('_', '-')}: {value}"
        for key, value in theme_values.items()
        if key.replace("_", "").isalnum() and value
    )

    return {
        "navigation": sections,
        "theme_css_vars": css_vars,
        "current_path": current_path,
        "page_item_map": page_item_map,
        "badge_counts": {
            "notifications": _safe_count(
                Notification, Notification.status.in_(("queued", "pending"))
            ),
            "orders": _safe_count(
                Order, Order.status.in_(("created", "awaiting_payment", "paid"))
            ),
            "unread_chats": _safe_count(
                Conversation, Conversation.status.in_(("open", "pending"))
            ),
        },
    }


def _safe_count(model, criterion=None):
    try:
        query = db.session.query(func.count(model.id))
        if criterion is not None:
            query = query.filter(criterion)
        return query.scalar() or 0
    except Exception:
        db.session.rollback()
        return 0
