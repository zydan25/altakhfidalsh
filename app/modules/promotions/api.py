from . import api_bp
from ...models import Campaign, Coupon, GiftCampaign


@api_bp.get("/campaigns")
def campaigns():
    rows = Campaign.query.filter_by(is_active=True).order_by(Campaign.display_priority.desc(), Campaign.id.desc()).all()
    return {"items": [{"id": x.id, "name": x.name, "slug": x.slug, "start_at": x.start_at.isoformat() if x.start_at else None, "end_at": x.end_at.isoformat() if x.end_at else None, "status": x.status} for x in rows]}


@api_bp.get("/coupons")
def coupons():
    rows = Coupon.query.filter_by(is_active=True).order_by(Coupon.id.desc()).limit(100).all()
    return {"items": [{"id": x.id, "code": x.code, "type": x.type, "value": str(x.value), "starts_at": x.starts_at.isoformat() if x.starts_at else None, "ends_at": x.ends_at.isoformat() if x.ends_at else None} for x in rows]}


@api_bp.get("/gifts")
def gifts():
    rows = GiftCampaign.query.filter_by(is_active=True).order_by(GiftCampaign.id.desc()).limit(100).all()
    return {"items": [{"id": x.id, "name": x.name, "gift_type": x.gift_type, "value": str(x.value) if x.value is not None else None} for x in rows]}
