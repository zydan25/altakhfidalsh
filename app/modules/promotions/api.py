from flask import request
from ...extensions import db

from . import api_bp
from ...security import admin_api_required
from .services import PromotionService
from ...extensions import db
from ...models import Campaign, Coupon, GiftCampaign


@api_bp.get("/campaigns")
def campaigns():
    rows = Campaign.query.filter_by(is_active=True).order_by(Campaign.display_priority.desc(), Campaign.id.desc()).all()
    return {"items": [{"id": x.id, "name": x.name, "slug": x.slug, "start_at": x.start_at.isoformat() if x.start_at else None, "end_at": x.end_at.isoformat() if x.end_at else None, "status": x.status} for x in rows]}


@api_bp.get("/coupons")
def coupons():
    rows = Coupon.query.filter_by(is_active=True).order_by(Coupon.id.desc()).limit(100).all()
    return {"items": [{"id": x.id, "code": x.code, "type": x.type, "value": str(x.value), "starts_at": x.starts_at.isoformat() if x.starts_at else None, "ends_at": x.ends_at.isoformat() if x.ends_at else None} for x in rows]}


@api_bp.post("/coupons/redeem")
def redeem_coupon():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": PromotionService.redeem_coupon(
            str(payload["code"]).strip(),
            int(payload["customer_id"]),
            payload.get("order_id"),
            payload["order_subtotal"],
        )}
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "coupon_redeem_failed", "detail": str(exc)}, 400


@api_bp.get("/gifts")
def gifts():
    rows = GiftCampaign.query.filter_by(is_active=True).order_by(GiftCampaign.id.desc()).limit(100).all()
    return {"items": [{"id": x.id, "name": x.name, "gift_type": x.gift_type, "value": str(x.value) if x.value is not None else None} for x in rows]}


@api_bp.post("/gifts/issue")
@admin_api_required("promotion.manage")
def issue_gift():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": PromotionService.issue_gift(int(payload["campaign_id"]), int(payload["customer_id"]))}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "gift_issue_failed", "detail": str(exc)}, 400


@api_bp.post("/wallet/adjust")
@admin_api_required("wallet.adjust")
def wallet_adjust():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": PromotionService.adjust_wallet(
            int(payload["customer_id"]),
            int(payload["currency_id"]),
            payload["amount"],
            str(payload["type"]),
            payload.get("reference_type"),
            payload.get("reference_id"),
        )}
    except (KeyError, ValueError) as exc:
        return {"error": "wallet_adjust_failed", "detail": str(exc)}, 400


@api_bp.post("/campaigns/<int:campaign_id>/products/<int:product_id>")
@admin_api_required("campaign.manage")
def attach_campaign_product(campaign_id, product_id):
    from ...models import Campaign, CampaignProduct, Product
    if db.session.get(Campaign, campaign_id) is None or db.session.get(Product, product_id) is None:
        return {"error": "not_found"}, 404
    from ...extensions import db
    if CampaignProduct.query.filter_by(campaign_id=campaign_id, product_id=product_id).first():
        return {"ok": True, "already_attached": True}
    row = CampaignProduct(campaign_id=campaign_id, product_id=product_id, sort_order=0)
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "campaign_id": campaign_id, "product_id": product_id}}, 201


@api_bp.post("/campaigns/<int:campaign_id>/categories/<int:category_id>")
@admin_api_required("campaign.manage")
def attach_campaign_category(campaign_id, category_id):
    from ...models import Campaign, CampaignCategory, Category
    if db.session.get(Campaign, campaign_id) is None or db.session.get(Category, category_id) is None:
        return {"error": "not_found"}, 404
    if CampaignCategory.query.filter_by(campaign_id=campaign_id, category_id=category_id).first():
        return {"ok": True, "already_attached": True}
    row = CampaignCategory(campaign_id=campaign_id, category_id=category_id, sort_order=0)
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "campaign_id": campaign_id, "category_id": category_id}}, 201


@api_bp.post("/campaigns/<int:campaign_id>/hashtags/<int:hashtag_id>")
@admin_api_required("campaign.manage")
def attach_campaign_hashtag(campaign_id, hashtag_id):
    from ...models import Campaign, CampaignHashtag, Hashtag
    if db.session.get(Campaign, campaign_id) is None or db.session.get(Hashtag, hashtag_id) is None:
        return {"error": "not_found"}, 404
    if CampaignHashtag.query.filter_by(campaign_id=campaign_id, hashtag_id=hashtag_id).first():
        return {"ok": True, "already_attached": True}
    row = CampaignHashtag(campaign_id=campaign_id, hashtag_id=hashtag_id)
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "campaign_id": campaign_id, "hashtag_id": hashtag_id}}, 201
