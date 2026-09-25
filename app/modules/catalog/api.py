from decimal import Decimal, InvalidOperation

from flask import request

from . import api_bp
from ...security import admin_api_required
from .services import CatalogService, MediaService


@api_bp.get("/categories")
def categories():
    return {"items": CatalogService.list_categories()}


@api_bp.post("/categories")
@admin_api_required("category.manage")
def create_category():
    payload = request.get_json(silent=True) or {}
    try:
        category = CatalogService.create_category(payload)
    except ValueError as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400
    return {"item": category}, 201


@api_bp.patch("/categories/<int:category_id>")
@admin_api_required("category.manage")
def update_category(category_id):
    payload = request.get_json(silent=True) or {}
    try:
        category = CatalogService.update_category(category_id, payload)
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400
    return {"item": category}


@api_bp.delete("/categories/<int:category_id>")
@admin_api_required("category.manage")
def delete_category(category_id):
    try:
        CatalogService.delete_category(category_id)
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400
    return {"ok": True}


@api_bp.get("/products")
def products():
    return {"items": CatalogService.list_products()}


@api_bp.post("/products/drafts")
@admin_api_required("product.create")
def create_draft_product():
    payload = request.get_json(silent=True) or {}
    try:
        product = CatalogService.create_draft(payload)
    except (ValueError, LookupError) as exc:
        return {"error": "invalid_product", "detail": str(exc)}, 400
    return {"item": product}, 201


@api_bp.get("/products/<int:product_id>")
def product_detail(product_id):
    try:
        return {"item": CatalogService.get_product(product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.patch("/products/<int:product_id>")
@admin_api_required("product.edit")
def update_product(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_product(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_product", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/publish")
@admin_api_required("product.publish")
def publish_product(product_id):
    try:
        return {"item": CatalogService.publish_product(product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "cannot_publish", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/categories")
@admin_api_required("product.edit")
def set_product_categories(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_categories(product_id, payload.get("category_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_categories", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/options")
@admin_api_required("product.edit")
def add_product_option(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.add_option(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_option", "detail": str(exc)}, 400


@api_bp.patch("/products/<int:product_id>/variants/<int:variant_id>")
@admin_api_required("product.edit")
def update_product_variant(product_id, variant_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_variant(product_id, variant_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_variant", "detail": str(exc)}, 400


@api_bp.delete("/products/<int:product_id>/variants/<int:variant_id>")
@admin_api_required("product.edit")
def archive_product_variant(product_id, variant_id):
    try:
        return {"item": CatalogService.archive_variant(product_id, variant_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.patch("/products/<int:product_id>/options/<int:option_id>")
@admin_api_required("product.edit")
def update_product_option(product_id, option_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_option(product_id, option_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_option", "detail": str(exc)}, 400


@api_bp.delete("/products/<int:product_id>/options/<int:option_id>")
@admin_api_required("product.edit")
def delete_product_option(product_id, option_id):
    try:
        return {"item": CatalogService.remove_option(product_id, option_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.post("/products/<int:product_id>/variants")
@admin_api_required("product.edit")
def add_product_variant(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.add_variant(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_variant", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/inventory")
@admin_api_required("inventory.manage")
def set_inventory(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_inventory(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_inventory", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/media")
@admin_api_required("product.edit")
def upload_product_media(product_id):
    try:
        items = MediaService.attach_product_files(product_id, request.files.getlist("files"), color_id=request.form.get("color_id", type=int))
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_media", "detail": str(exc)}, 400
    return {"items": items}, 201



@api_bp.get("/reference/product-config")
def product_config_references():
    product_id = request.args.get("product_id", type=int)
    try:
        return {"item": CatalogService.product_reference_data(product_id=product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.post("/reference/categories")
@admin_api_required("category.manage")
def create_category_reference():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_category(payload)}, 201
    except (LookupError, ValueError, TypeError) as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400


@api_bp.get("/reference/options")
def option_references():
    product_id = request.args.get("product_id", type=int)
    return {"item": CatalogService.option_references(product_id=product_id)}


@api_bp.get("/reference/marketing")
def marketing_references():
    from ...models import Badge, Brand, Hashtag
    return {
        "brands": [
            {"id": x.id, "name": x.name, "slug": x.slug, "logo_asset_id": x.logo_asset_id}
            for x in Brand.query.filter_by(is_active=True).order_by(Brand.name).all()
        ],
        "badges": [
            {
                "id": x.id,
                "name": x.name,
                "code": x.code,
                "bg_color": x.bg_color,
                "text_color": x.text_color,
                "style": x.style,
            }
            for x in Badge.query.filter_by(is_active=True).order_by(Badge.priority.desc(), Badge.name).all()
        ],
        "hashtags": [
            {"id": x.id, "name": x.name, "slug": x.slug, "display_name": x.display_name}
            for x in Hashtag.query.filter_by(is_active=True).order_by(Hashtag.sort_order, Hashtag.name).all()
        ],
    }


@api_bp.post("/products/<int:product_id>/promotional-strips")
@admin_api_required("product.edit")
def set_product_promotional_strips(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_promotional_strips(product_id, payload.get("strip_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_promotional_strips", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/campaigns")
@admin_api_required("product.edit")
def set_product_campaigns(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_campaigns(product_id, payload.get("campaign_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_campaigns", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/badges")
@admin_api_required("product.edit")
def set_product_badges(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_badges(product_id, payload.get("badge_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_badges", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/hashtags")
@admin_api_required("product.edit")
def set_product_hashtags(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_hashtags(product_id, payload.get("hashtag_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_hashtags", "detail": str(exc)}, 400


@api_bp.get("/inventory-locations")
def inventory_locations():
    return {"items": CatalogService.list_inventory_locations()}


@api_bp.post("/inventory-locations")
@admin_api_required("inventory.manage")
def create_inventory_location():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_inventory_location(payload)}, 201
    except ValueError as exc:
        return {"error": "invalid_inventory_location", "detail": str(exc)}, 400

@api_bp.post("/products/<int:product_id>/display-settings")
@admin_api_required("product.edit")
def display_settings(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_display_settings(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_display_settings", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/policies")
@admin_api_required("product.edit")
def product_policies(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_policies(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_policy_assignment", "detail": str(exc)}, 400



@api_bp.post("/categories/<int:category_id>/filters")
@admin_api_required("category.manage")
def create_filter(category_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_filter(category_id, payload)}, 201
    except LookupError as exc:
        return {"error": "category_not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "filter_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/categories/<int:category_id>/filters")
def category_filters(category_id):
    try:
        return {"items": CatalogService.category_filters(category_id)}
    except LookupError as exc:
        return {"error": "category_not_found", "detail": str(exc)}, 404


@api_bp.post("/filters/<int:filter_id>/values")
@admin_api_required("category.manage")
def create_filter_value(filter_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_filter_value(filter_id, payload)}, 201
    except LookupError as exc:
        return {"error": "filter_not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "filter_value_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/filter-values")
@admin_api_required("product.edit")
def set_product_filter_values(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_filter_values(product_id, payload.get("value_ids", []))}
    except LookupError as exc:
        return {"error": "product_not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "product_filter_values_failed", "detail": str(exc)}, 400

@api_bp.get("/products/<int:product_id>/wizard")
def product_wizard(product_id):
    try:
        return {"item": CatalogService.wizard_snapshot(product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.post("/reference/colors")
@admin_api_required("product.edit")
def create_color():
    payload = request.get_json(silent=True) or {}
    try:
        from ...extensions import db
        from ...models import Color
        name = str(payload.get("name") or "").strip()
        if not name:
            raise ValueError("اسم اللون مطلوب.")
        hex_code = (payload.get("hex_code") or "").strip() or None
        duplicate = Color.query.filter(Color.name == name, Color.is_active.is_(True)).first()
        if duplicate:
            raise ValueError("هذا اللون موجود مسبقًا.")
        color = Color(
            name=name,
            hex_code=hex_code,
            swatch_asset_id=payload.get("swatch_asset_id"),
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(color)
        db.session.commit()
        return {"item": {
            "id": color.id,
            "name": color.name,
            "hex_code": color.hex_code,
            "swatch_asset_id": color.swatch_asset_id,
        }}, 201
    except (KeyError, TypeError, ValueError) as exc:
        db.session.rollback() if "db" in locals() else None
        return {"error": "invalid_color", "detail": str(exc)}, 400


@api_bp.post("/reference/sizes")
@admin_api_required("product.edit")
def create_size():
    payload = request.get_json(silent=True) or {}
    try:
        from ...extensions import db
        from ...models import Size
        group = str(payload.get("group") or "").strip()
        code = str(payload.get("code") or "").strip().upper()
        label = str(payload.get("label") or "").strip()
        if not group or not code or not label:
            raise ValueError("مجموعة المقاس والكود والاسم الظاهر مطلوبة.")
        if Size.query.filter_by(group=group, code=code).first():
            raise ValueError("كود المقاس مستخدم داخل المجموعة.")
        size = Size(
            group=group,
            code=code,
            label=label,
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(size)
        db.session.commit()
        return {"item": {"id": size.id, "group": size.group, "code": size.code, "label": size.label}}, 201
    except (KeyError, TypeError, ValueError) as exc:
        db.session.rollback() if "db" in locals() else None
        return {"error": "invalid_size", "detail": str(exc)}, 400


@api_bp.get("/reference/policies")
def policy_references():
    from ...models import ReturnPolicy, ShippingPolicy, WarrantyPolicy
    return {
        "shipping": [{"id": x.id, "name": x.name, "delivery_window": x.delivery_window} for x in ShippingPolicy.query.filter_by(is_active=True).order_by(ShippingPolicy.name).all()],
        "return": [{"id": x.id, "name": x.name, "return_window_days": x.return_window_days} for x in ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.name).all()],
        "warranty": [{"id": x.id, "name": x.name, "duration_days": x.duration_days} for x in WarrantyPolicy.query.filter_by(is_active=True).order_by(WarrantyPolicy.name).all()],
    }


@api_bp.post("/reference/brands")
@admin_api_required("product.edit")
def create_brand_reference():
    from ...extensions import db
    from ...models import Brand
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    if not name:
        return {"error": "invalid_brand", "detail": "اسم العلامة التجارية مطلوب."}, 400
    slug = str(payload.get("slug") or "").strip().lower()
    if not slug:
        from .services import _slugify
        slug = _slugify(name, fallback="brand")
    base_slug = slug
    index = 2
    while Brand.query.filter_by(slug=slug).first() is not None:
        slug = f"{base_slug}-{index}"[:180]
        index += 1
    row = Brand(name=name, slug=slug, logo_asset_id=payload.get("logo_asset_id"))
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "slug": row.slug, "is_active": bool(row.is_active)}}, 201


@api_bp.post("/reference/hashtags")
@admin_api_required("product.edit")
def create_hashtag_reference():
    from ...extensions import db
    from ...models import Hashtag
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    display_name = str(payload.get("display_name") or "").strip() or None
    if not name:
        return {"error": "invalid_hashtag", "detail": "اسم الهاشتاج مطلوب."}, 400
    slug = str(payload.get("slug") or "").strip().lower()
    if not slug:
        from .services import _slugify
        slug = _slugify(display_name or name, fallback="tag")
    base_slug = slug
    index = 2
    while Hashtag.query.filter_by(slug=slug).first() is not None:
        slug = f"{base_slug}-{index}"[:180]
        index += 1
    row = Hashtag(name=name, slug=slug, display_name=display_name, sort_order=int(payload.get("sort_order", 0)))
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "slug": row.slug, "display_name": row.display_name, "is_active": bool(row.is_active)}}, 201


@api_bp.post("/reference/promotional-strips")
@admin_api_required("product.edit")
def create_promotional_strip_reference():
    from ...extensions import db
    from ...models import PromotionalStrip
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    text_body = str(payload.get("text_body") or "").strip()
    if not name or not text_body:
        return {"error": "invalid_promotional_strip", "detail": "اسم الشريط والنص مطلوبان."}, 400
    row = PromotionalStrip(
        name=name,
        text_prefix=str(payload.get("text_prefix") or "").strip() or None,
        text_body=text_body,
        background_color=str(payload.get("background_color") or "").strip() or None,
        text_color=str(payload.get("text_color") or "").strip() or None,
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "text_body": row.text_body, "is_active": bool(row.is_active)}}, 201


@api_bp.post("/reference/campaigns")
@admin_api_required("product.edit")
def create_campaign_reference():
    from ...extensions import db
    from ...models import Campaign, Badge
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    if not name:
        return {"error": "invalid_campaign", "detail": "اسم الحملة مطلوب."}, 400
    slug = str(payload.get("slug") or "").strip().lower()
    if not slug:
        from .services import _slugify
        slug = _slugify(name, fallback="campaign")
    base_slug = slug
    index = 2
    while Campaign.query.filter_by(slug=slug).first() is not None:
        slug = f"{base_slug}-{index}"[:200]
        index += 1
    badge_id = payload.get("badge_id")
    if badge_id not in (None, "") and db.session.get(Badge, int(badge_id)) is None:
        return {"error": "invalid_campaign", "detail": "الشارة المختارة غير موجودة."}, 400
    row = Campaign(
        name=name,
        slug=slug,
        badge_id=int(badge_id) if badge_id not in (None, "") else None,
        status=str(payload.get("status") or "draft").strip(),
        display_priority=int(payload.get("display_priority", 0)),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "slug": row.slug, "status": row.status, "is_active": bool(row.is_active)}}, 201


@api_bp.post("/policies/shipping")
@admin_api_required("policy.manage")
def create_shipping_policy():
    from ...extensions import db
    from ...models import ShippingPolicy
    payload = request.get_json(silent=True) or {}
    row = ShippingPolicy(
        name=str(payload["name"]).strip(),
        free_shipping_enabled=bool(payload.get("free_shipping_enabled", False)),
        min_order_amount=payload.get("min_order_amount"),
        promo_text=payload.get("promo_text"),
        delivery_window=payload.get("delivery_window"),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name}}, 201


@api_bp.post("/policies/return")
@admin_api_required("policy.manage")
def create_return_policy():
    from ...extensions import db
    from ...models import ReturnPolicy
    payload = request.get_json(silent=True) or {}
    row = ReturnPolicy(
        name=str(payload["name"]).strip(),
        return_window_days=int(payload.get("return_window_days", 0)),
        conditions=payload.get("conditions"),
        fee_rule=payload.get("fee_rule"),
        refund_method=payload.get("refund_method"),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "return_window_days": row.return_window_days}}, 201


@api_bp.post("/policies/warranty")
@admin_api_required("policy.manage")
def create_warranty_policy():
    from ...extensions import db
    from ...models import WarrantyPolicy
    payload = request.get_json(silent=True) or {}
    row = WarrantyPolicy(
        name=str(payload["name"]).strip(),
        duration_days=int(payload.get("duration_days", 0)),
        coverage=payload.get("coverage"),
        exclusions=payload.get("exclusions"),
        claim_method=payload.get("claim_method"),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "duration_days": row.duration_days}}, 201


@api_bp.post("/badges")
@admin_api_required("product.edit")
def create_badge():
    from ...extensions import db
    from ...models import Badge
    payload = request.get_json(silent=True) or {}
    try:
        name = str(payload.get("name") or "").strip()
        code = str(payload.get("code") or "").strip().lower()
        if not name or not code:
            raise ValueError("اسم الشارة والكود مطلوبان.")
        if Badge.query.filter_by(code=code).first():
            raise ValueError("كود الشارة مستخدم مسبقًا.")
        row = Badge(
            name=name,
            code=code,
            icon_asset_id=payload.get("icon_asset_id"),
            bg_color=(payload.get("bg_color") or "").strip() or None,
            text_color=(payload.get("text_color") or "").strip() or None,
            style=(payload.get("style") or "solid").strip(),
            priority=int(payload.get("priority", 0)),
        )
        db.session.add(row)
        db.session.commit()
        return {"item": {
            "id": row.id, "name": row.name, "code": row.code,
            "bg_color": row.bg_color, "text_color": row.text_color,
            "style": row.style, "priority": row.priority,
        }}, 201
    except (TypeError, ValueError) as exc:
        db.session.rollback()
        return {"error": "invalid_badge", "detail": str(exc)}, 400


@api_bp.post("/size-guides")
@admin_api_required("product.edit")
def create_size_guide():
    from ...extensions import db
    from ...models import SizeGuide, SizeGuideRow
    payload = request.get_json(silent=True) or {}
    guide = SizeGuide(
        name=str(payload["name"]).strip(),
        guide_type=str(payload.get("guide_type", "product")),
        fit_type=payload.get("fit_type"),
        intro_text=payload.get("intro_text"),
    )
    db.session.add(guide)
    db.session.flush()
    for raw in payload.get("rows", []):
        db.session.add(SizeGuideRow(
            guide_id=guide.id,
            size_id=int(raw["size_id"]),
            product_measurements=raw.get("product_measurements") or {},
            body_measurements=raw.get("body_measurements") or {},
        ))
    db.session.commit()
    return {"item": {"id": guide.id, "name": guide.name, "guide_type": guide.guide_type}}, 201


@api_bp.get("/size-guides")
def size_guides():
    from ...models import SizeGuide, SizeGuideRow
    rows = SizeGuide.query.filter_by(is_active=True).order_by(SizeGuide.name).all()
    return {"items": [
        {
            "id": x.id,
            "name": x.name,
            "guide_type": x.guide_type,
            "fit_type": x.fit_type,
            "intro_text": x.intro_text,
            "rows": [
                {
                    "id": row.id,
                    "size_id": row.size_id,
                    "product_measurements": row.product_measurements,
                    "body_measurements": row.body_measurements,
                }
                for row in SizeGuideRow.query.filter_by(guide_id=x.id).order_by(SizeGuideRow.id).all()
            ],
        }
        for x in rows
    ]}


@api_bp.post("/products/<int:product_id>/garment-size-settings")
@admin_api_required("product.edit")
def garment_size_settings(product_id):
    from ...extensions import db
    from ...models import GarmentSizeSetting
    if db.session.get(Product, product_id) is None:
        return {"error": "product_not_found"}, 404
    payload = request.get_json(silent=True) or {}
    row = db.session.get(GarmentSizeSetting, product_id)
    if row is None:
        row = GarmentSizeSetting(product_id=product_id)
        db.session.add(row)
    row.model_asset_id = payload.get("model_asset_id")
    row.displayed_sizes = payload.get("displayed_sizes") or []
    row.measurements_mode = str(payload.get("measurements_mode", "body"))
    row.image_zoom = Decimal(str(payload.get("image_zoom", 1)))
    db.session.commit()
    return {"item": {"product_id": row.product_id, "model_asset_id": row.model_asset_id, "displayed_sizes": row.displayed_sizes, "measurements_mode": row.measurements_mode, "image_zoom": str(row.image_zoom)}}


@api_bp.delete("/products/<int:product_id>/media/<int:media_id>")
@admin_api_required("product.edit")
def delete_product_media(product_id, media_id):
    try:
        return {"item": CatalogService.remove_product_media(product_id, media_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
