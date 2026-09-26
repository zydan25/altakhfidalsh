from datetime import datetime, timezone
from flask import request

from . import api_bp
from ...security import admin_api_required
from ...extensions import db
from ...models import Banner, BannerTarget, Campaign, Category, Hashtag, Look, LookProduct, LookCircle, SideCategory, SideCategoryCircle, MediaAsset, Product, StorefrontPage, StorefrontSection, StorefrontSectionItem
from sqlalchemy import or_


@api_bp.get("/pages")
def pages():
    items = StorefrontPage.query.filter_by(is_active=True).order_by(StorefrontPage.id).all()
    return {"items": [{"id": x.id, "code": x.code, "name": x.name, "route": x.route} for x in items]}


@api_bp.post("/pages")
@admin_api_required("content.manage")
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
@admin_api_required("content.manage")
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
@admin_api_required("content.manage")
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
@admin_api_required("banner.manage")
def create_banner():
    payload = request.get_json(silent=True) or {}
    try:
        root_category_id = payload.get("root_category_id")
        if root_category_id is not None:
            root = db.session.get(Category, int(root_category_id))
            if root is None or not root.is_active or root.parent_id is not None:
                return {"error": "invalid_banner", "detail": "root_category must be a top-level active category"}, 400
        row = Banner(
            name=str(payload["name"]).strip(),
            image_asset_id=int(payload["image_asset_id"]),
            mobile_asset_id=int(payload["mobile_asset_id"]) if payload.get("mobile_asset_id") else None,
            root_category_id=int(root_category_id) if root_category_id else None,
            title=payload.get("title"),
            description=payload.get("description"),
            button_label=payload.get("button_label"),
            title_color=payload.get("title_color", "#ffffff"),
            description_color=payload.get("description_color", "#ffffff"),
            button_text_color=payload.get("button_text_color", "#ffffff"),
            button_background_color=payload.get("button_background_color", "#111827"),
            overlay_background_color=payload.get("overlay_background_color", "#111827"),
            overlay_opacity=payload.get("overlay_opacity", 0),
            size_spec=payload.get("size_spec"),
            overlay_text=payload.get("overlay_text"),
            position_text=payload.get("position_text", "center"),
            duration=int(payload.get("duration", 6)),
            sort_order=int(payload.get("sort_order", 0)),
            status="draft",
        )
    except (KeyError, ValueError):
        return {"error": "invalid_banner"}, 400
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "status": row.status}}, 201


@api_bp.post("/banners/<int:banner_id>/targets")
@admin_api_required("banner.manage")
def add_banner_target(banner_id):
    payload = request.get_json(silent=True) or {}
    if db.session.get(Banner, banner_id) is None:
        return {"error": "not_found"}, 404
    target_type = str(payload["target_type"]).strip()
    if target_type not in {"category", "campaign", "hashtag", "product", "style_tab", "url"}:
        return {"error": "invalid_target_type"}, 400
    target_id = payload.get("target_id")
    mapping = {"category": Category, "campaign": Campaign, "hashtag": Hashtag, "product": Product}
    if target_type == "style_tab":
        if target_id not in (None, "", 0, "0"):
            try:
                target_id = int(target_id)
            except (TypeError, ValueError):
                return {"error": "invalid_target"}, 400
            if db.session.get(Look, target_id) is None:
                return {"error": "look_not_found"}, 404
        else:
            target_id = None
    elif target_type in mapping:
        try:
            target_id = int(target_id)
        except (TypeError, ValueError):
            return {"error": "invalid_target"}, 400
        if db.session.get(mapping[target_type], target_id) is None:
            return {"error": "target_not_found"}, 404
    else:
        target_id = None
    target = BannerTarget(
        banner_id=banner_id,
        target_type=target_type,
        target_id=target_id,
        url=payload.get("url") or ("/looks" if target_type == "style_tab" else None),
        config_json=payload.get("config_json") or {},
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
    now = datetime.now(timezone.utc)
    rows = (
        Banner.query
        .filter(
            Banner.is_active.is_(True),
            Banner.status == "active",
            or_(Banner.starts_at.is_(None), Banner.starts_at <= now),
            or_(Banner.ends_at.is_(None), Banner.ends_at >= now),
        )
        .order_by(Banner.sort_order, Banner.id.desc())
        .all()
    )
    asset_ids = []
    for row in rows:
        asset_ids.append(row.image_asset_id)
        if row.mobile_asset_id:
            asset_ids.append(row.mobile_asset_id)
    assets = MediaAsset.query.filter(MediaAsset.id.in_(asset_ids)).all() if asset_ids else []
    asset_urls = {x.id: x.url for x in assets}
    items = []
    for row in rows:
        target_rows = BannerTarget.query.filter_by(banner_id=row.id).order_by(
            BannerTarget.priority.desc(), BannerTarget.id
        ).all()
        items.append({
            "id": row.id,
            "name": row.name,
            "title": row.title,
            "description": row.description,
            "button_label": row.button_label,
            "image_url": asset_urls.get(row.image_asset_id),
            "mobile_image_url": asset_urls.get(row.mobile_asset_id) if row.mobile_asset_id else None,
            "root_category_id": row.root_category_id,
            "overlay_text": row.overlay_text,
            "position_text": row.position_text,
            "duration": row.duration,
            "title_color": row.title_color,
            "description_color": row.description_color,
            "button_text_color": row.button_text_color,
            "button_background_color": row.button_background_color,
            "overlay_background_color": row.overlay_background_color,
            "overlay_opacity": float(row.overlay_opacity or 0),
            "sort_order": row.sort_order,
            "targets": [
                {
                    "type": target.target_type,
                    "id": target.target_id,
                    "url": target.url,
                    "config": target.config_json or {},
                    "priority": target.priority,
                }
                for target in target_rows
            ],
        })
    return {"items": items}


@api_bp.get("/looks")
def looks():
    now = datetime.now(timezone.utc)
    rows = Look.query.filter(
        Look.is_active.is_(True),
        Look.status == "active",
        or_(Look.starts_at.is_(None), Look.starts_at <= now),
        or_(Look.ends_at.is_(None), Look.ends_at >= now),
    ).order_by(Look.sort_order, Look.id.desc()).all()
    asset_ids = [x.cover_asset_id for x in rows if x.cover_asset_id]
    assets = MediaAsset.query.filter(MediaAsset.id.in_(asset_ids)).all() if asset_ids else []
    asset_urls = {x.id: x.url for x in assets}
    return {
        "items": [
            {
                "id": look.id,
                "name": look.name,
                "slug": look.slug,
                "description": look.description,
                "cover_url": asset_urls.get(look.cover_asset_id),
                "starts_at": look.starts_at.isoformat() if look.starts_at else None,
                "ends_at": look.ends_at.isoformat() if look.ends_at else None,
                "products": [
                    item.product_id
                    for item in LookProduct.query.filter_by(look_id=look.id).order_by(LookProduct.sort_order, LookProduct.id).all()
                ],
                "circles": [
                    {
                        "id": circle.id,
                        "name": circle.name,
                        "slug": circle.slug,
                        "side_category_id": circle.side_category_id,
                        "sort_order": link.sort_order,
                        "image_url": (
                            MediaAsset.query.get(circle.image_asset_id).url
                            if circle.image_asset_id else None
                        ),
                    }
                    for link in LookCircle.query.filter_by(look_id=look.id).order_by(LookCircle.sort_order, LookCircle.id).all()
                    for circle in [db.session.get(SideCategoryCircle, link.circle_id)]
                    if circle is not None and circle.is_active
                ],
            }
            for look in rows
        ]
    }


@api_bp.post("/navigation-actions")
@admin_api_required("content.manage")
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
@admin_api_required("content.manage")
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
