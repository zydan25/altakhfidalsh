from flask import render_template, request
from sqlalchemy import func

from .navigation import NAVIGATION
from ..extensions import db
from ..models import Category, Conversation, Customer, Order, Product


def _safe_count(model):
    try:
        return db.session.query(func.count(model.id)).scalar() or 0
    except Exception:
        db.session.rollback()
        return 0


def _navigation_context():
    current_path = request.path
    page_item_map = []
    for section in NAVIGATION:
        section.active = any(
            current_path == child.route or current_path.startswith(child.route + "/")
            for child in section.children
        )
        for child in section.children:
            page_item_map.append(
                {
                    "label": child.label,
                    "route": child.route,
                    "section": section.label,
                }
            )
    return {
        "navigation": NAVIGATION,
        "current_path": current_path,
        "page_item_map": page_item_map,
    }


def register_admin_routes(admin_bp):
    @admin_bp.get("/")
    def dashboard():
        context = _navigation_context()
        metrics = {
            "products": _safe_count(Product),
            "categories": _safe_count(Category),
            "orders": _safe_count(Order),
            "customers": _safe_count(Customer),
            "conversations": _safe_count(Conversation),
        }
        return render_template(
            "admin/dashboard.html",
            title="لوحة الإدارة",
            metrics=metrics,
            **context,
        )

    @admin_bp.get("/<path:subpath>")
    def module_shell(subpath):
        context = _navigation_context()
        requested = "/" + subpath.rstrip("/")
        title = "وحدة الإدارة"
        section = "النظام"
        for item in context["page_item_map"]:
            if requested == item["route"]:
                title = item["label"]
                section = item["section"]
                break
        return render_template(
            "admin/module.html",
            title=title,
            section=section,
            requested_path=requested,
            **context,
        )
