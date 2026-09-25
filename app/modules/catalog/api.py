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


@api_bp.get("/products/<int:product_id>/wizard")
def product_wizard(product_id):
    try:
        return {"item": CatalogService.wizard_snapshot(product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
