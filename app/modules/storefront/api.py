from flask import request

from . import api_bp
from ...extensions import db
from ...models import Banner, BannerTarget, StorefrontPage, StorefrontSection, StorefrontSectionItem


@api_bp.get("/pages")
def pages():
    items = StorefrontPage.query.filter_by(is_active=True).order_by(StorefrontPage.id).all()
    return {"items": [{"id": x.id, "code": x.code, "name": x.name, "route": x.route} for x in items]}


@api_bp.post("/pages")
def create_page():
    payload = request.get_json(silent=True) or {}
    code = str(payload.get("code", "")).strip()
    name = str(payload.get("name", "")).strip()
    route = str(payload.get("route", "")).strip()
    if not code or not name or not route:
        return {"error": "invalid_page", "detail": "code, name and route are required"}, 400
    if StorefrontPage.query.filter((StorefrontPage.code == code) | (StorefrontPage.route == route)).first():
        return {"error": "invalid_page", "detail": "page code or route already exists"}, 400
    row = StorefrontPage(code=code, name=name, route=route)
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "code": row.code, "name": row.name, "route": row.route}}, 201


@api_bp.post("/pages/<int:page_id>/sections")
def create_section(page_id):
    payload = request.get_json(silent=True) or {}
    if db.session.get(StorefrontPage, page_id) is None:
        return {"error": "not_found"}, 404
    row = StorefrontSection(
        page_id=page_id,
        section_type=str(payload.get("section_type", "product_grid")),
        title=payload.get("title"),
        settings=payload.get("settings") or {},
        sort_order=int(payload.get("sort_order", 0)),
        visible_rules=payload.get("visible_rules") or {},
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "page_id": row.page_id, "section_type": row.section_type}}, 201


@api_bp.post("/sections/<int:section_id>/items")
def add_section_item(section_id):
    payload = request.get_json(silent=True) or {}
    if db.session.get(StorefrontSection, section_id) is None:
        return {"error": "not_found"}, 404
    item = StorefrontSectionItem(
        section_id=section_id,
        item_type=str(payload["item_type"]),
        item_id=int(payload["item_id"]),
        sort_order=int(payload.get("sort_order", 0)),
        custom_label=payload.get("custom_label"),
    )
    db.session.add(item)
    db.session.commit()
    return {"item": {"id": item.id, "section_id": item.section_id, "item_type": item.item_type, "item_id": item.item_id}}, 201


@api_bp.post("/banners")
def create_banner():
    payload = request.get_json(silent=True) or {}
    try:
        row = Banner(
            name=str(payload["name"]).strip(),
            image_asset_id=int(payload["image_asset_id"]),
            mobile_asset_id=payload.get("mobile_asset_id"),
            size_spec=payload.get("size_spec"),
            overlay_text=payload.get("overlay_text"),
            position_text=payload.get("position_text"),
            duration=payload.get("duration"),
            status="draft",
        )
    except (KeyError, ValueError):
        return {"error": "invalid_banner"}, 400
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "status": row.status}}, 201


@api_bp.post("/banners/<int:banner_id>/targets")
def add_banner_target(banner_id):
    payload = request.get_json(silent=True) or {}
    if db.session.get(Banner, banner_id) is None:
        return {"error": "not_found"}, 404
    target = BannerTarget(
        banner_id=banner_id,
        target_type=str(payload["target_type"]),
        target_id=payload.get("target_id"),
        url=payload.get("url"),
        priority=int(payload.get("priority", 0)),
    )
    db.session.add(target)
    db.session.commit()
    return {"item": {"id": target.id, "target_type": target.target_type, "target_id": target.target_id, "url": target.url}}, 201


@api_bp.get("/pages/<string:code>")
def page(code):
    page = StorefrontPage.query.filter_by(code=code, is_active=True).first()
    if page is None:
        return {"error": "not_found"}, 404
    sections = StorefrontSection.query.filter_by(page_id=page.id).order_by(StorefrontSection.sort_order, StorefrontSection.id).all()
    return {
        "page": {"id": page.id, "code": page.code, "name": page.name, "route": page.route},
        "sections": [
            {
                "id": section.id,
                "type": section.section_type,
                "title": section.title,
                "settings": section.settings,
                "sort_order": section.sort_order,
                "items": [
                    {
                        "id": item.id,
                        "type": item.item_type,
                        "item_id": item.item_id,
                        "sort_order": item.sort_order,
                        "custom_label": item.custom_label,
                    }
                    for item in StorefrontSectionItem.query.filter_by(section_id=section.id).order_by(StorefrontSectionItem.sort_order).all()
                ],
            }
            for section in sections
        ],
    }


@api_bp.get("/banners")
def banners():
    rows = Banner.query.filter_by(is_active=True).order_by(Banner.id.desc()).all()
    return {"items": [{"id": x.id, "name": x.name, "image_asset_id": x.image_asset_id, "mobile_asset_id": x.mobile_asset_id, "status": x.status} for x in rows]}


@api_bp.post("/navigation-actions")
def create_navigation_action():
    payload = request.get_json(silent=True) or {}
    from ...models import NavigationAction
    code = str(payload["code"]).strip().lower()
    if NavigationAction.query.filter_by(code=code).first():
        return {"error": "duplicate_code"}, 400
    row = NavigationAction(
        code=code,
        label=str(payload["label"]).strip(),
        icon=payload.get("icon"),
        route=payload.get("route"),
        sort_order=int(payload.get("sort_order", 0)),
        visibility_rule=payload.get("visibility_rule") or {},
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "code": row.code, "label": row.label, "route": row.route}}, 201


@api_bp.get("/navigation-actions")
def navigation_actions():
    from ...models import NavigationAction
    rows = NavigationAction.query.filter_by(is_active=True).order_by(NavigationAction.sort_order, NavigationAction.id).all()
    return {"items": [{"id": x.id, "code": x.code, "label": x.label, "icon": x.icon, "route": x.route, "visibility_rule": x.visibility_rule} for x in rows]}


@api_bp.post("/category-navigation")
def category_navigation():
    payload = request.get_json(silent=True) or {}
    from ...models import CategoryNavigationItem
    category_id = int(payload["category_id"])
    if db.session.get(__import__("app.models", fromlist=["Category"]).Category, category_id) is None:
        return {"error": "category_not_found"}, 404
    row = CategoryNavigationItem(
        category_id=category_id,
        slot=str(payload.get("slot", "top")),
        visible=bool(payload.get("visible", True)),
        sort_order=int(payload.get("sort_order", 0)),
        label_override=payload.get("label_override"),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "category_id": row.category_id, "sort_order": row.sort_order}}, 201


@api_bp.get("/category-navigation")
def category_navigation_list():
    from ...models import CategoryNavigationItem
    rows = CategoryNavigationItem.query.filter_by(is_active=True, visible=True).order_by(CategoryNavigationItem.sort_order, CategoryNavigationItem.id).all()
    return {"items": [{"id": x.id, "category_id": x.category_id, "slot": x.slot, "sort_order": x.sort_order, "label_override": x.label_override} for x in rows]}
