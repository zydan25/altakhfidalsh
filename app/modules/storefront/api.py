import json
from datetime import datetime, timezone
from flask import request

from . import api_bp
from ...security import admin_api_required
from ...extensions import db
from ...models import Banner, BannerTarget, Campaign, Category, Hashtag, Look, LookTarget, LookProduct, LookCircle, SideCategory, SideCategoryCircle, MediaAsset, Product, StorefrontPage, StorefrontSection, StorefrontSectionItem, HomeCouponDisplaySetting, HomeCouponCard, AppSetting
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
            header_top_background_color=payload.get("header_top_background_color", "#111827"),
            header_category_text_color=payload.get("header_category_text_color", "#ffffff"),
            header_category_active_color=payload.get("header_category_active_color", "#ffffff"),
            overlay_opacity=payload.get("overlay_opacity", 0),
            size_spec=payload.get("size_spec"),
            overlay_text=payload.get("overlay_text"),
            position_text=payload.get("position_text", "center"),
            button_position=payload.get("button_position", "same"),
            overlay_font_size=int(payload.get("overlay_font_size", 13)),
            title_font_size=int(payload.get("title_font_size", 28)),
            description_font_size=int(payload.get("description_font_size", 16)),
            button_font_size=int(payload.get("button_font_size", 11)),
            button_radius=int(payload.get("button_radius", 0)),
            content_padding=int(payload.get("content_padding", 18)),
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




def _coupon_defaults():
    return {
        "enabled": True,
        "auto_flip": True,
        "flip_seconds": 4,
        "cards_per_slide": 2,
        "card_height": 64,
        "card_radius": 14,
        "card_spacing": 6,
        "title_font_size": 16,
        "subtitle_font_size": 11,
        "badge_font_size": 10,
        "default_background_color": "#E2EFDA",
        "default_text_color": "#1B5E20",
        "default_badge_background_color": "#166534",
        "default_badge_text_color": "#FFFFFF",
    }


def _serialize_coupon_card(card):
    target = None
    if card.display_type == "redirect" and card.target_type:
        target = {
            "type": card.target_type,
            "id": card.target_id,
            "url": card.target_url,
        }
        if card.target_type == "category" and card.target_id:
            item = db.session.get(Category, card.target_id)
            if item is not None:
                target["name"] = item.name
        elif card.target_type == "product" and card.target_id:
            item = db.session.get(Product, card.target_id)
            if item is not None:
                target["name"] = item.name
        elif card.target_type == "hashtag" and card.target_id:
            item = db.session.get(Hashtag, card.target_id)
            if item is not None:
                target["name"] = item.display_name or item.name
    return {
        "id": card.id,
        "name": card.name,
        "root_category_id": card.root_category_id,
        "display_type": card.display_type,
        "code": card.code,
        "headline": card.headline,
        "subtitle": card.subtitle,
        "badge_text": card.badge_text,
        "icon_type": card.icon_type,
        "target": target,
        "background_color": card.background_color,
        "text_color": card.text_color,
        "badge_background_color": card.badge_background_color,
        "badge_text_color": card.badge_text_color,
        "border_color": card.border_color,
        "sort_order": card.sort_order,
        "duration": card.duration,
    }



def _store_locations_payload():
    row = AppSetting.query.filter_by(
        group_code="storefront",
        key="store_locations_json",
    ).first()
    locations = []
    if row and row.value:
        try:
            raw = json.loads(row.value)
            if isinstance(raw, list):
                locations = [dict(x) for x in raw if isinstance(x, dict)]
        except (TypeError, ValueError):
            locations = []

    if not locations:
        values = {}
        for key in (
            "store_name",
            "store_address",
            "store_latitude",
            "store_longitude",
            "store_map_url",
        ):
            setting = AppSetting.query.filter_by(
                group_code="storefront",
                key=key,
            ).first()
            if setting and (setting.value or "").strip():
                values[key] = setting.value.strip()
        if values:
            locations = [{
                "id": "legacy-store",
                "name": values.get("store_name") or "موقع المتجر",
                "region": "",
                "city": "",
                "address": values.get("store_address") or "",
                "map_url": values.get("store_map_url") or "",
                "latitude": values.get("store_latitude") or "",
                "longitude": values.get("store_longitude") or "",
                "images": [],
            }]

    asset_ids = {
        int(image.get("id"))
        for location in locations
        for image in (location.get("images") or [])
        if isinstance(image, dict) and str(image.get("id") or "").isdigit()
    }
    assets = (
        MediaAsset.query.filter(
            MediaAsset.id.in_(asset_ids),
            MediaAsset.is_active.is_(True),
        ).all()
        if asset_ids else []
    )
    asset_urls = {asset.id: asset.url for asset in assets}

    items = []
    for location in locations:
        images = []
        for image in location.get("images") or []:
            if not isinstance(image, dict):
                continue
            asset_id = int(image.get("id") or 0)
            url = asset_urls.get(asset_id) or image.get("url")
            if url:
                images.append({
                    "id": asset_id,
                    "url": url,
                })
        items.append({
            "id": str(location.get("id") or ""),
            "name": str(location.get("name") or "").strip(),
            "region": str(location.get("region") or "").strip(),
            "city": str(location.get("city") or "").strip(),
            "address": str(location.get("address") or "").strip(),
            "map_url": str(location.get("map_url") or "").strip(),
            "latitude": str(location.get("latitude") or "").strip(),
            "longitude": str(location.get("longitude") or "").strip(),
            "images": images,
        })
    return items

def _coupon_payload():
    now = datetime.now(timezone.utc)
    defaults = _coupon_defaults()
    settings_rows = HomeCouponDisplaySetting.query.order_by(
        HomeCouponDisplaySetting.root_category_id.is_(None).desc(),
        HomeCouponDisplaySetting.root_category_id,
    ).all()
    settings_all = dict(defaults)
    settings_categories = {}
    for row in settings_rows:
        values = {
            "enabled": bool(row.enabled),
            "auto_flip": bool(row.auto_flip),
            "flip_seconds": int(row.flip_seconds),
            "cards_per_slide": int(row.cards_per_slide),
            "card_height": int(row.card_height),
            "card_radius": int(row.card_radius),
            "card_spacing": int(row.card_spacing),
            "title_font_size": int(row.title_font_size),
            "subtitle_font_size": int(row.subtitle_font_size),
            "badge_font_size": int(row.badge_font_size),
            "default_background_color": row.default_background_color,
            "default_text_color": row.default_text_color,
            "default_badge_background_color": row.default_badge_background_color,
            "default_badge_text_color": row.default_badge_text_color,
        }
        if row.root_category_id is None:
            settings_all.update(values)
        else:
            settings_categories[str(row.root_category_id)] = values

    rows = HomeCouponCard.query.filter(
        HomeCouponCard.is_active.is_(True),
        or_(HomeCouponCard.starts_at.is_(None), HomeCouponCard.starts_at <= now),
        or_(HomeCouponCard.ends_at.is_(None), HomeCouponCard.ends_at >= now),
    ).order_by(
        HomeCouponCard.root_category_id,
        HomeCouponCard.sort_order,
        HomeCouponCard.id.desc(),
    ).all()
    all_cards = []
    category_cards = {}
    for card in rows:
        item = _serialize_coupon_card(card)
        if card.root_category_id is None:
            all_cards.append(item)
        else:
            category_cards.setdefault(str(card.root_category_id), []).append(item)
    return {
        "all": settings_all,
        "categories": settings_categories,
        "cards": {
            "all": all_cards,
            "categories": category_cards,
        },
    }


@api_bp.get("/home")
def home():
    """Single discovery payload for the customer storefront."""
    from ..catalog.services import CatalogService

    page = StorefrontPage.query.filter_by(code="home", is_active=True).first()
    page_payload = None
    if page:
        sections = StorefrontSection.query.filter_by(page_id=page.id).order_by(
            StorefrontSection.sort_order, StorefrontSection.id
        ).all()
        page_payload = {
            "id": page.id,
            "code": page.code,
            "name": page.name,
            "route": page.route,
            "sections": [
                {
                    "id": section.id,
                    "type": section.section_type,
                    "title": section.title,
                    "settings": section.settings or {},
                    "sort_order": section.sort_order,
                    "items": [
                        {
                            "id": item.id,
                            "type": item.item_type,
                            "item_id": item.item_id,
                            "sort_order": item.sort_order,
                            "custom_label": item.custom_label,
                        }
                        for item in StorefrontSectionItem.query.filter_by(
                            section_id=section.id
                        ).order_by(StorefrontSectionItem.sort_order, StorefrontSectionItem.id).all()
                    ],
                }
                for section in sections
            ],
        }

    root_category_id = request.args.get("root_category_id", type=int)
    banner_payload = banners(root_category_id=root_category_id).get("items", [])
    look_payload = looks().get("items", [])

    header_gap_row = AppSetting.query.filter_by(
        group_code="storefront", key="home_header_category_gap"
    ).first()
    try:
        header_category_gap = int(str(header_gap_row.value).strip()) if header_gap_row and header_gap_row.value is not None else 3
    except (TypeError, ValueError):
        header_category_gap = 3
    header_category_gap = max(-30, min(120, header_category_gap))
    return {
        "ui_settings": {
            "home_header_category_gap": header_category_gap,
        },
        "page": page_payload,
        "categories": CatalogService.list_categories(),
        "category_display": CatalogService.list_home_category_display(),
        "side_categories": CatalogService.list_side_categories(
            root_category_id=root_category_id,
            include_archived=False,
        ),
        "side_circle_display": CatalogService.get_side_circle_display(),
        "side_circle_groups": CatalogService.list_side_circle_groups(
            include_archived=False,
            public_scope=False,
        ),
        "trends": CatalogService.list_public_trends(limit=20),
        "trend_hashtags": CatalogService.list_public_trend_hashtags(limit=500),
        "trend_settings": CatalogService.trend_display_settings(),
        "product_card_settings": CatalogService.product_card_display_settings(),
        "looks": look_payload,
        "banners": banner_payload,
        "coupon_strip": _coupon_payload(),
    }

@api_bp.get("/store-locations")
def store_locations():
    return {"items": _store_locations_payload()}

@api_bp.get("/banners")
def banners(root_category_id=None):
    now = datetime.now(timezone.utc)
    rows = (
        Banner.query
        .filter(
            Banner.is_active.is_(True),
            Banner.status == "active",
            or_(Banner.starts_at.is_(None), Banner.starts_at <= now),
            or_(Banner.ends_at.is_(None), Banner.ends_at >= now),
            (
                Banner.root_category_id.is_(None)
                if root_category_id == -1
                else Banner.root_category_id == root_category_id
            )
            if root_category_id is not None
            else True,
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
            "button_position": row.button_position,
            "overlay_font_size": row.overlay_font_size,
            "title_font_size": row.title_font_size,
            "description_font_size": row.description_font_size,
            "button_font_size": row.button_font_size,
            "button_radius": row.button_radius,
            "content_padding": row.content_padding,
            "duration": row.duration,
            "title_color": row.title_color,
            "description_color": row.description_color,
            "button_text_color": row.button_text_color,
            "button_background_color": row.button_background_color,
            "overlay_background_color": row.overlay_background_color,
            "header_top_background_color": row.header_top_background_color,
            "header_category_text_color": row.header_category_text_color,
            "header_category_active_color": row.header_category_active_color,
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
        Look.show_on_home.is_(True),
        or_(Look.starts_at.is_(None), Look.starts_at <= now),
        or_(Look.ends_at.is_(None), Look.ends_at >= now),
    ).order_by(
        Look.root_category_id,
        Look.sort_order,
        Look.id.desc(),
    ).all()
    asset_ids = [x.cover_asset_id for x in rows if x.cover_asset_id]
    assets = MediaAsset.query.filter(MediaAsset.id.in_(asset_ids)).all() if asset_ids else []
    asset_urls = {x.id: x.url for x in assets}
    items = []
    for look in rows:
        target_rows = LookTarget.query.filter_by(look_id=look.id).order_by(
            LookTarget.priority.desc(), LookTarget.id
        ).all()

        targets = []
        for target in target_rows:
            item = {
                "id": target.id,
                "type": target.target_type,
                "target_id": target.target_id,
                "priority": target.priority,
            }
            if target.target_type == "circle":
                circle = db.session.get(SideCategoryCircle, target.target_id)
                if circle is not None and circle.is_active:
                    item["name"] = circle.name
                    item["image_url"] = (
                        db.session.get(MediaAsset, circle.image_asset_id).url
                        if circle.image_asset_id else None
                    )
                    targets.append(item)
            elif target.target_type == "hashtag":
                hashtag = db.session.get(Hashtag, target.target_id)
                if hashtag is not None and hashtag.is_active:
                    item["name"] = hashtag.display_name or hashtag.name
                    item["slug"] = hashtag.slug
                    targets.append(item)

        items.append({
            "id": look.id,
            "name": look.name,
            "slug": look.slug,
            "description": look.description,
            "root_category_id": look.root_category_id,
            "show_on_home": bool(look.show_on_home),
            "card_shape": look.card_shape,
            "card_width": look.card_width,
            "card_height": look.card_height,
            "card_radius": look.card_radius,
            "card_spacing": look.card_spacing,
            "caption_background_color": look.caption_background_color,
            "caption_text_color": look.caption_text_color,
            "caption_height": look.caption_height,
            "caption_font_size": look.caption_font_size,
            "cover_url": asset_urls.get(look.cover_asset_id),
            "starts_at": look.starts_at.isoformat() if look.starts_at else None,
            "ends_at": look.ends_at.isoformat() if look.ends_at else None,
            "products": [
                item.product_id
                for item in LookProduct.query.filter_by(look_id=look.id)
                .order_by(LookProduct.sort_order, LookProduct.id)
                .all()
            ],
            "circles": [
                {
                    "id": circle.id,
                    "name": circle.name,
                    "slug": circle.slug,
                    "side_category_id": circle.side_category_id,
                    "sort_order": link.sort_order,
                    "image_url": (
                        db.session.get(MediaAsset, circle.image_asset_id).url
                        if circle.image_asset_id else None
                    ),
                }
                for link in LookCircle.query.filter_by(look_id=look.id)
                .order_by(LookCircle.sort_order, LookCircle.id)
                .all()
                for circle in [db.session.get(SideCategoryCircle, link.circle_id)]
                if circle is not None and circle.is_active
            ],
            "targets": targets,
        })
    return {"items": items}


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
