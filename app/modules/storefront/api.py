from flask import request

from . import api_bp
from ...models import Banner, Category, StorefrontPage, StorefrontSection, StorefrontSectionItem


@api_bp.get("/pages")
def pages():
    items = StorefrontPage.query.filter_by(is_active=True).order_by(StorefrontPage.id).all()
    return {"items": [{"id": x.id, "code": x.code, "name": x.name, "route": x.route} for x in items]}


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
