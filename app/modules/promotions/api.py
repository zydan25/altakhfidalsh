from flask import request

from . import api_bp
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
def issue_gift():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": PromotionService.issue_gift(int(payload["campaign_id"]), int(payload["customer_id"]))}, 201
    except (KeyError, ValueError, LookupError) as exc:
        return {"error": "gift_issue_failed", "detail": str(exc)}, 400


@api_bp.post("/wallet/adjust")
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
