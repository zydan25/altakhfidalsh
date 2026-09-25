from decimal import Decimal, InvalidOperation

from flask import request

from . import api_bp
from .services import CatalogService, MediaService


@api_bp.get("/categories")
def categories():
    return {"items": CatalogService.list_categories()}


@api_bp.post("/categories")
def create_category():
    payload = request.get_json(silent=True) or {}
    try:
        category = CatalogService.create_category(payload)
    except ValueError as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400
    return {"item": category}, 201


@api_bp.patch("/categories/<int:category_id>")
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
def update_product(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_product(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_product", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/publish")
def publish_product(product_id):
    try:
        return {"item": CatalogService.publish_product(product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "cannot_publish", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/categories")
def set_product_categories(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_categories(product_id, payload.get("category_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_categories", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/options")
def add_product_option(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.add_option(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_option", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/variants")
def add_product_variant(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.add_variant(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_variant", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/inventory")
def set_inventory(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_inventory(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_inventory", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/media")
def upload_product_media(product_id):
    try:
        items = MediaService.attach_product_files(product_id, request.files.getlist("files"))
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_media", "detail": str(exc)}, 400
    return {"items": items}, 201



@api_bp.get("/reference/options")
def option_references():
    return {"item": CatalogService.option_references()}


@api_bp.get("/inventory-locations")
def inventory_locations():
    return {"items": CatalogService.list_inventory_locations()}


@api_bp.post("/inventory-locations")
def create_inventory_location():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_inventory_location(payload)}, 201
    except ValueError as exc:
        return {"error": "invalid_inventory_location", "detail": str(exc)}, 400

@api_bp.post("/products/<int:product_id>/display-settings")
def display_settings(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_display_settings(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_display_settings", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/policies")
def product_policies(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_policies(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_policy_assignment", "detail": str(exc)}, 400



@api_bp.post("/categories/<int:category_id>/filters")
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
def create_filter_value(filter_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_filter_value(filter_id, payload)}, 201
    except LookupError as exc:
        return {"error": "filter_not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "filter_value_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/filter-values")
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
def create_color():
    payload = request.get_json(silent=True) or {}
    try:
        from ...models import Color
        color = Color(
            name=str(payload["name"]).strip(),
            hex_code=(payload.get("hex_code") or "").strip() or None,
            swatch_asset_id=payload.get("swatch_asset_id"),
            sort_order=int(payload.get("sort_order", 0)),
        )
        __import__("app.extensions", fromlist=["db"]).db.session.add(color)
        __import__("app.extensions", fromlist=["db"]).db.session.commit()
        return {"item": {"id": color.id, "name": color.name, "hex_code": color.hex_code}}, 201
    except KeyError as exc:
        return {"error": "invalid_color", "detail": str(exc)}, 400


@api_bp.post("/reference/sizes")
def create_size():
    payload = request.get_json(silent=True) or {}
    try:
        from ...models import Size
        size = Size(
            group=str(payload["group"]).strip(),
            code=str(payload["code"]).strip().upper(),
            label=str(payload["label"]).strip(),
            sort_order=int(payload.get("sort_order", 0)),
        )
        __import__("app.extensions", fromlist=["db"]).db.session.add(size)
        __import__("app.extensions", fromlist=["db"]).db.session.commit()
        return {"item": {"id": size.id, "group": size.group, "code": size.code, "label": size.label}}, 201
    except KeyError as exc:
        return {"error": "invalid_size", "detail": str(exc)}, 400


@api_bp.get("/reference/policies")
def policy_references():
    from ...models import ReturnPolicy, ShippingPolicy, WarrantyPolicy
    return {
        "shipping": [{"id": x.id, "name": x.name, "delivery_window": x.delivery_window} for x in ShippingPolicy.query.filter_by(is_active=True).order_by(ShippingPolicy.name).all()],
        "return": [{"id": x.id, "name": x.name, "return_window_days": x.return_window_days} for x in ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.name).all()],
        "warranty": [{"id": x.id, "name": x.name, "duration_days": x.duration_days} for x in WarrantyPolicy.query.filter_by(is_active=True).order_by(WarrantyPolicy.name).all()],
    }


@api_bp.post("/policies/shipping")
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
def create_badge():
    from ...extensions import db
    from ...models import Badge
    payload = request.get_json(silent=True) or {}
    row = Badge(
        name=str(payload["name"]).strip(),
        code=str(payload["code"]).strip().lower(),
        icon_asset_id=payload.get("icon_asset_id"),
        bg_color=payload.get("bg_color"),
        text_color=payload.get("text_color"),
        style=payload.get("style"),
        priority=int(payload.get("priority", 0)),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "code": row.code}}, 201


@api_bp.post("/size-guides")
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
