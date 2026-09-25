from flask import request

from . import api_bp
from .services import AfterSalesService
from ...extensions import db
from ...models import Review, ReviewMedia, WarrantyClaim


@api_bp.post("/returns")
def create_return():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": AfterSalesService.create_return(payload)}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "return_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/warranty/claims")
def warranty_claim():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": AfterSalesService.create_warranty_claim(payload)}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "warranty_claim_failed", "detail": str(exc)}, 400


@api_bp.post("/reviews")
def create_review():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": AfterSalesService.create_review(payload)}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "review_creation_failed", "detail": str(exc)}, 400


@api_bp.get("/reviews/product/<int:product_id>")
def product_reviews(product_id):
    rows = Review.query.filter_by(product_id=product_id, is_active=True, status="approved").order_by(Review.id.desc()).limit(100).all()
    return {
        "items": [
            {
                "id": x.id,
                "customer_id": x.customer_id,
                "order_item_id": x.order_item_id,
                "rating": x.rating,
                "title": x.title,
                "body": x.body,
                "created_at": x.created_at.isoformat(),
                "media": [
                    {"id": media.id, "asset_id": media.asset_id}
                    for media in ReviewMedia.query.filter_by(review_id=x.id).all()
                ],
            }
            for x in rows
        ]
    }


@api_bp.get("/warranty/claims/<int:claim_id>")
def warranty_claim_detail(claim_id):
    row = db.session.get(WarrantyClaim, claim_id)
    if row is None:
        return {"error": "not_found"}, 404
    return {"item": {
        "id": row.id,
        "customer_id": row.customer_id,
        "order_id": row.order_id,
        "order_item_id": row.order_item_id,
        "issue": row.issue,
        "description": row.description,
        "status": row.status,
        "resolution": row.resolution,
    }}
