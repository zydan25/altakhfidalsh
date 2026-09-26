from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from uuid import uuid4

from PIL import Image, ImageOps
from flask import current_app
from sqlalchemy import or_

from ...extensions import db
from ...models import (
    Category,
    Color,
    Currency,
    MediaAsset,
    Product,
    ProductCategory,
    ProductDisplaySettings,
    ProductFilterValue,
    CategoryFilterDefinition,
    CategoryFilterValue,
    ProductMedia,
    ProductOption,
    ProductOptionValue,
    ProductVariant,
    StockInventory,
    InventoryLocation,
    ProductPolicyAssignment,
    ShippingPolicy,
    ReturnPolicy,
    WarrantyPolicy,
    VariantOptionValue,
    ProductBadge,
    Badge,
    Brand,
    Hashtag,
    ProductHashtag,
    PromotionalStrip,
    ProductPromotionalStrip,
    Campaign,
    CampaignProduct,
    Trend,
    TrendProduct,
    SideCategory,
    SideCategoryCircle,
    ProductSideCategoryCircle,
    SizeGuide,
    ProductColorReference,
    ProductSizeReference,
)


_ARABIC_SLUG_MAP = str.maketrans({
    "ا":"a","أ":"a","إ":"i","آ":"a","ب":"b","ت":"t","ث":"th","ج":"j","ح":"h","خ":"kh",
    "د":"d","ذ":"th","ر":"r","ز":"z","س":"s","ش":"sh","ص":"s","ض":"d","ط":"t","ظ":"z",
    "ع":"a","غ":"gh","ف":"f","ق":"q","ك":"k","ل":"l","م":"m","ن":"n","ه":"h","و":"w",
    "ي":"y","ى":"a","ة":"h","ؤ":"w","ئ":"y","ء":"","ـ":""
})


def _slugify(value, fallback="item"):
    import re
    value = (value or "").strip().lower().translate(_ARABIC_SLUG_MAP)
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value[:220] or fallback


class CatalogService:
    @staticmethod
    def _serialize_category(category):
        return {
            "id": category.id,
            "parent_id": category.parent_id,
            "name": category.name,
            "slug": category.slug,
            "display_style": category.display_style,
            "icon_asset_id": category.icon_asset_id,
            "badge_id": category.badge_id,
            "sort_order": category.sort_order,
            "is_active": category.is_active,
        }

    @staticmethod
    def list_categories():
        rows = (
            Category.query
            .filter(Category.is_active.is_(True))
            .order_by(Category.parent_id, Category.sort_order, Category.name)
            .all()
        )
        return [CatalogService._serialize_category(row) for row in rows]

    @staticmethod
    def _require_top_level_category(category_id):
        category = db.session.get(Category, int(category_id))
        if category is None or not category.is_active:
            raise ValueError("القسم الرئيسي غير موجود أو مؤرشف.")
        if category.parent_id is not None:
            raise ValueError("الفئة الجانبية ترتبط بقسم رئيسي فقط، ولا يمكن اختيار فئة فرعية.")
        return category

    @staticmethod
    def _serialize_side_category_circle(circle, include_products=False):
        asset = db.session.get(MediaAsset, circle.image_asset_id) if circle.image_asset_id else None
        badge = db.session.get(Badge, circle.badge_id) if circle.badge_id else None
        payload = {
            "id": circle.id,
            "side_category_id": circle.side_category_id,
            "name": circle.name,
            "slug": circle.slug,
            "image_asset_id": circle.image_asset_id,
            "image_url": asset.url if asset else None,
            "badge_id": circle.badge_id,
            "badge": {
                "id": badge.id,
                "name": badge.name,
                "bg_color": badge.bg_color,
                "text_color": badge.text_color,
            } if badge else None,
            "sort_order": circle.sort_order,
            "is_active": bool(circle.is_active),
        }
        if include_products:
            payload["product_count"] = (
                db.session.query(ProductSideCategoryCircle.id)
                .join(Product, Product.id == ProductSideCategoryCircle.product_id)
                .filter(
                    ProductSideCategoryCircle.circle_id == circle.id,
                    Product.is_active.is_(True),
                    Product.status == "published",
                )
                .count()
            )
        return payload

    @staticmethod
    def _serialize_side_category(side_category, include_circles=True):
        root = db.session.get(Category, side_category.root_category_id)
        badge = db.session.get(Badge, side_category.badge_id) if side_category.badge_id else None
        circles = []
        if include_circles:
            circles = [
                CatalogService._serialize_side_category_circle(row, include_products=True)
                for row in SideCategoryCircle.query
                .filter(
                    SideCategoryCircle.side_category_id == side_category.id,
                    SideCategoryCircle.is_active.is_(True),
                )
                .order_by(SideCategoryCircle.sort_order, SideCategoryCircle.name)
                .all()
            ]
        return {
            "id": side_category.id,
            "root_category_id": side_category.root_category_id,
            "root_category_name": root.name if root else "—",
            "name": side_category.name,
            "slug": side_category.slug,
            "badge_id": side_category.badge_id,
            "badge": {
                "id": badge.id,
                "name": badge.name,
                "bg_color": badge.bg_color,
                "text_color": badge.text_color,
            } if badge else None,
            "sort_order": side_category.sort_order,
            "is_active": bool(side_category.is_active),
            "circles": circles,
        }

    @staticmethod
    def list_side_categories(root_category_id=None, include_archived=False):
        query = SideCategory.query
        if not include_archived:
            query = query.filter(SideCategory.is_active.is_(True))
        if root_category_id:
            query = query.filter(SideCategory.root_category_id == int(root_category_id))
        return [
            CatalogService._serialize_side_category(row)
            for row in query.order_by(SideCategory.sort_order, SideCategory.name, SideCategory.id).all()
        ]

    @staticmethod
    def create_side_category(payload):
        root_id = payload.get("root_category_id")
        name = (payload.get("name") or "").strip()
        if not root_id or not name:
            raise ValueError("القسم الرئيسي واسم الفئة الجانبية مطلوبان.")
        CatalogService._require_top_level_category(root_id)
        slug = (payload.get("slug") or "").strip().lower() or _slugify(name, fallback="side-category")
        base_slug = slug
        idx = 2
        while SideCategory.query.filter_by(root_category_id=int(root_id), slug=slug).first():
            slug = f"{base_slug}-{idx}"[:180]
            idx += 1
        row = SideCategory(
            root_category_id=int(root_id),
            name=name,
            slug=slug,
            badge_id=int(payload["badge_id"]) if payload.get("badge_id") else None,
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(row)
        db.session.commit()
        return CatalogService._serialize_side_category(row)

    @staticmethod
    def update_side_category(side_category_id, payload):
        row = db.session.get(SideCategory, side_category_id)
        if row is None:
            raise LookupError("side category not found")
        if "root_category_id" in payload:
            CatalogService._require_top_level_category(payload["root_category_id"])
            row.root_category_id = int(payload["root_category_id"])
        if "name" in payload:
            name = (payload.get("name") or "").strip()
            if not name:
                raise ValueError("اسم الفئة الجانبية مطلوب.")
            row.name = name
        if "slug" in payload and (payload.get("slug") or "").strip():
            row.slug = _slugify(payload["slug"], fallback=f"side-category-{row.id}")
        if "badge_id" in payload:
            row.badge_id = int(payload["badge_id"]) if payload.get("badge_id") else None
        if "sort_order" in payload:
            row.sort_order = int(payload["sort_order"])
        duplicate = (
            SideCategory.query
            .filter(
                SideCategory.id != row.id,
                SideCategory.root_category_id == row.root_category_id,
                SideCategory.slug == row.slug,
            )
            .first()
        )
        if duplicate:
            db.session.rollback()
            raise ValueError("Slug الفئة الجانبية مستخدم داخل القسم الرئيسي.")
        db.session.commit()
        return CatalogService._serialize_side_category(row)

    @staticmethod
    def archive_side_category(side_category_id):
        row = db.session.get(SideCategory, side_category_id)
        if row is None:
            raise LookupError("side category not found")
        row.is_active = False
        SideCategoryCircle.query.filter_by(side_category_id=row.id).update({"is_active": False})
        db.session.commit()

    @staticmethod
    def create_side_category_circle(side_category_id, payload, files=None):
        side = db.session.get(SideCategory, int(side_category_id))
        if side is None or not side.is_active:
            raise LookupError("side category not found")
        name = (payload.get("name") or "").strip()
        if not name:
            raise ValueError("اسم الدائرة مطلوب.")
        slug = (payload.get("slug") or "").strip().lower() or _slugify(name, fallback="circle")
        base_slug = slug
        idx = 2
        while SideCategoryCircle.query.filter_by(side_category_id=side.id, slug=slug).first():
            slug = f"{base_slug}-{idx}"[:180]
            idx += 1
        asset_id = None
        if files:
            assets = MediaService.save_generic_files(files, f"side-categories/{side.id}/circles")
            asset_id = assets[0]["id"] if assets else None
        row = SideCategoryCircle(
            side_category_id=side.id,
            name=name,
            slug=slug,
            image_asset_id=asset_id,
            badge_id=int(payload["badge_id"]) if payload.get("badge_id") else None,
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(row)
        db.session.commit()
        return CatalogService._serialize_side_category_circle(row, include_products=True)

    @staticmethod
    def update_side_category_circle(circle_id, payload, files=None):
        row = db.session.get(SideCategoryCircle, circle_id)
        if row is None:
            raise LookupError("side category circle not found")
        if "name" in payload:
            name = (payload.get("name") or "").strip()
            if not name:
                raise ValueError("اسم الدائرة مطلوب.")
            row.name = name
        if "slug" in payload and (payload.get("slug") or "").strip():
            row.slug = _slugify(payload["slug"], fallback=f"circle-{row.id}")
        if "badge_id" in payload:
            row.badge_id = int(payload["badge_id"]) if payload.get("badge_id") else None
        if "sort_order" in payload:
            row.sort_order = int(payload["sort_order"])
        if files:
            assets = MediaService.save_generic_files(files, f"side-categories/{row.side_category_id}/circles")
            if assets:
                row.image_asset_id = assets[0]["id"]
        duplicate = (
            SideCategoryCircle.query
            .filter(
                SideCategoryCircle.id != row.id,
                SideCategoryCircle.side_category_id == row.side_category_id,
                SideCategoryCircle.slug == row.slug,
            )
            .first()
        )
        if duplicate:
            db.session.rollback()
            raise ValueError("Slug دائرة التصنيف مستخدم داخل الفئة الجانبية.")
        db.session.commit()
        return CatalogService._serialize_side_category_circle(row, include_products=True)

    @staticmethod
    def archive_side_category_circle(circle_id):
        row = db.session.get(SideCategoryCircle, circle_id)
        if row is None:
            raise LookupError("side category circle not found")
        row.is_active = False
        db.session.commit()

    @staticmethod
    def set_product_side_category_circles(product_id, circle_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        normalized = []
        for raw in circle_ids or []:
            circle_id = int(raw)
            circle = db.session.get(SideCategoryCircle, circle_id)
            if circle is None or not circle.is_active:
                raise ValueError("إحدى دوائر الفئات الجانبية غير موجودة أو مؤرشفة.")
            if circle_id not in normalized:
                normalized.append(circle_id)
        ProductSideCategoryCircle.query.filter_by(product_id=product_id).delete()
        for position, circle_id in enumerate(normalized):
            db.session.add(ProductSideCategoryCircle(
                product_id=product_id,
                circle_id=circle_id,
                sort_order=position,
            ))
        db.session.commit()
        return normalized

    @staticmethod
    def list_product_side_category_circles(product_id):
        return [
            int(row.circle_id)
            for row in ProductSideCategoryCircle.query
            .filter_by(product_id=product_id)
            .order_by(ProductSideCategoryCircle.sort_order, ProductSideCategoryCircle.id)
            .all()
        ]

    @staticmethod
    def create_category(payload):
        name = (payload.get("name") or "").strip()
        slug = (payload.get("slug") or "").strip().lower()
        parent_id = payload.get("parent_id")
        if not name:
            raise ValueError("name is required")
        if not slug:
            slug = _slugify(name, fallback="category")
        if parent_id is not None and not db.session.get(Category, int(parent_id)):
            raise ValueError("parent category was not found")
        base_slug = slug
        index = 2
        while Category.query.filter_by(parent_id=parent_id, slug=slug).first() is not None:
            slug = f"{base_slug}-{index}"[:180]
            index += 1

        category = Category(
            name=name,
            slug=slug,
            parent_id=int(parent_id) if parent_id is not None else None,
            display_style=(payload.get("display_style") or "circle").strip(),
            sort_order=int(payload.get("sort_order", 0)),
            is_featured=bool(payload.get("is_featured", False)),
        )
        db.session.add(category)
        db.session.commit()
        return CatalogService._serialize_category(category)

    @staticmethod
    def update_category(category_id, payload):
        category = db.session.get(Category, category_id)
        if not category:
            raise LookupError("category not found")
        if "parent_id" in payload:
            parent_id = payload["parent_id"]
            if parent_id == category_id:
                raise ValueError("category cannot be its own parent")
            if parent_id is not None:
                parent = db.session.get(Category, int(parent_id))
                if parent is None:
                    raise ValueError("parent category was not found")
            category.parent_id = parent_id
        if "name" in payload:
            category.name = (payload["name"] or "").strip()
        if "slug" in payload:
            category.slug = (payload["slug"] or "").strip().lower()
        if "display_style" in payload:
            category.display_style = payload["display_style"]
        if "sort_order" in payload:
            category.sort_order = int(payload["sort_order"])
        if "is_featured" in payload:
            category.is_featured = bool(payload["is_featured"])

        duplicate = (
            Category.query
            .filter(
                Category.id != category.id,
                Category.parent_id == category.parent_id,
                Category.slug == category.slug,
            )
            .first()
        )
        if duplicate:
            db.session.rollback()
            raise ValueError("slug already exists at this level")

        db.session.commit()
        return CatalogService._serialize_category(category)

    @staticmethod
    def delete_category(category_id):
        category = db.session.get(Category, category_id)
        if not category:
            raise LookupError("category not found")
        child = Category.query.filter_by(parent_id=category_id, is_active=True).first()
        if child:
            raise ValueError("move or delete child categories first")
        category.is_active = False
        db.session.commit()

    @staticmethod
    def _serialize_product(product):
        return {
            "id": product.id,
            "sku": product.sku,
            "name": product.name,
            "slug": product.slug,
            "description": product.description,
            "base_price_sar": str(product.base_price),
            "compare_at_price": str(product.compare_at_price) if product.compare_at_price is not None else None,
            "base_currency_id": product.base_currency_id,
            "status": product.status,
            "material": product.material,
            "care_instructions": product.care_instructions,
            "brand_id": product.brand_id,
            "product_type": product.product_type,
        }

    @staticmethod
    def list_products():
        rows = Product.query.order_by(Product.id.desc()).limit(100).all()
        return [CatalogService._serialize_product(row) for row in rows]

    @staticmethod
    def _require_sar(currency_id):
        currency = db.session.get(Currency, currency_id)
        if currency is None or currency.code != "SAR":
            raise ValueError("base product currency must be SAR")

    @staticmethod
    def create_draft(payload):
        sku = (payload.get("sku") or "").strip().upper()
        name = (payload.get("name") or "").strip()
        if not sku or not name:
            raise ValueError("sku and name are required")
        if Product.query.filter_by(sku=sku).first():
            raise ValueError("sku already exists")

        currency_id = payload.get("base_currency_id")
        if currency_id is None:
            currency = Currency.query.filter_by(code="SAR").first()
            if currency is None:
                raise LookupError("SAR currency is not configured")
            currency_id = currency.id
        CatalogService._require_sar(int(currency_id))

        try:
            base_price = Decimal(str(payload.get("base_price", "0")))
            compare_at_price = (
                Decimal(str(payload["compare_at_price"]))
                if payload.get("compare_at_price") not in (None, "")
                else None
            )
        except (InvalidOperation, ValueError):
            raise ValueError("invalid product price")
        if base_price < 0 or (compare_at_price is not None and compare_at_price < 0):
            raise ValueError("price cannot be negative")

        slug_base = _slugify(payload.get("slug") or name, fallback="product")
        slug = slug_base
        index = 2
        while Product.query.filter_by(slug=slug).first():
            slug = f"{slug_base}-{index}"[:220]
            index += 1

        product = Product(
            sku=sku,
            name=name,
            slug=slug,
            description=(payload.get("description") or "").strip() or None,
            base_currency_id=int(currency_id),
            base_price=base_price,
            compare_at_price=compare_at_price,
            status="draft",
            material=(payload.get("material") or "").strip() or None,
            care_instructions=(payload.get("care_instructions") or "").strip() or None,
        )
        db.session.add(product)
        db.session.flush()

        category_ids = [int(x) for x in payload.get("category_ids", [])]
        for index, category_id in enumerate(category_ids):
            category = db.session.get(Category, category_id)
            if category is None:
                raise ValueError(f"category {category_id} not found")
            db.session.add(ProductCategory(
                product_id=product.id,
                category_id=category_id,
                is_primary=(index == 0),
            ))
        db.session.commit()
        return CatalogService._serialize_product(product)

    @staticmethod
    def get_product(product_id):
        product = db.session.get(Product, product_id)
        if not product:
            raise LookupError("product not found")
        return CatalogService.wizard_snapshot(product_id)

    @staticmethod
    def update_product(product_id, payload):
        product = db.session.get(Product, product_id)
        if not product:
            raise LookupError("product not found")
        for key in ("name", "description", "material", "care_instructions", "sku", "product_type"):
            if key in payload:
                value = (payload[key] or "").strip()
                if key == "sku":
                    value = value.upper()
                    duplicate = Product.query.filter(Product.id != product_id, Product.sku == value).first()
                    if duplicate:
                        raise ValueError("sku already exists")
                if key == "name" and value:
                    requested_slug = (payload.get("slug") or "").strip()
                    slug_base = _slugify(requested_slug or value, fallback=f"product-{product_id}")
                    slug = slug_base
                    index = 2
                    while Product.query.filter(Product.id != product_id, Product.slug == slug).first():
                        slug = f"{slug_base}-{index}"[:220]
                        index += 1
                    product.slug = slug
                setattr(product, key, value or None)
        if "slug" in payload and (payload.get("slug") or "").strip():
            slug_base = _slugify(payload.get("slug"), fallback=f"product-{product_id}")
            slug = slug_base
            index = 2
            while Product.query.filter(Product.id != product_id, Product.slug == slug).first():
                slug = f"{slug_base}-{index}"[:220]
                index += 1
            product.slug = slug
        if "brand_id" in payload:
            brand_id = payload.get("brand_id")
            if brand_id in (None, ""):
                product.brand_id = None
            else:
                if db.session.get(Brand, int(brand_id)) is None:
                    raise ValueError("brand not found")
                product.brand_id = int(brand_id)

        if "base_price" in payload:
            price = Decimal(str(payload["base_price"]))
            if price < 0:
                raise ValueError("price cannot be negative")
            product.base_price = price
        if "compare_at_price" in payload:
            product.compare_at_price = (
                Decimal(str(payload["compare_at_price"]))
                if payload["compare_at_price"] not in (None, "")
                else None
            )
        db.session.commit()
        return CatalogService._serialize_product(product)

    @staticmethod
    def set_product_reference_dimensions(product_id, color_ids, size_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")

        normalized_colors = []
        for raw in color_ids or []:
            color_id = int(raw)
            if db.session.get(Color, color_id) is None:
                raise ValueError(f"color {color_id} not found")
            if color_id not in normalized_colors:
                normalized_colors.append(color_id)

        from ...models import Size
        normalized_sizes = []
        for raw in size_ids or []:
            size_id = int(raw)
            if db.session.get(Size, size_id) is None:
                raise ValueError(f"size {size_id} not found")
            if size_id not in normalized_sizes:
                normalized_sizes.append(size_id)

        active_variants = ProductVariant.query.filter_by(product_id=product_id, is_active=True).all()
        used_color_ids = {int(v.color_id) for v in active_variants if v.color_id is not None}
        used_size_ids = {int(v.size_id) for v in active_variants if v.size_id is not None}
        removed_colors = used_color_ids.difference(normalized_colors)
        removed_sizes = used_size_ids.difference(normalized_sizes)
        if removed_colors:
            raise ValueError("لا يمكن إزالة لون مستخدم في Variant نشط.")
        if removed_sizes:
            raise ValueError("لا يمكن إزالة مقاس مستخدم في Variant نشط.")

        ProductColorReference.query.filter_by(product_id=product_id).delete()
        for position, color_id in enumerate(normalized_colors):
            db.session.add(ProductColorReference(product_id=product_id, color_id=color_id, sort_order=position))

        ProductSizeReference.query.filter_by(product_id=product_id).delete()
        for position, size_id in enumerate(normalized_sizes):
            db.session.add(ProductSizeReference(product_id=product_id, size_id=size_id, sort_order=position))

        db.session.commit()
        return {"color_ids": normalized_colors, "size_ids": normalized_sizes}

    @staticmethod
    def set_product_badges(product_id, badge_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        normalized = []
        for raw in badge_ids:
            badge_id = int(raw)
            if db.session.get(Badge, badge_id) is None:
                raise ValueError(f"badge {badge_id} not found")
            if badge_id not in normalized:
                normalized.append(badge_id)
        ProductBadge.query.filter_by(product_id=product_id).delete()
        for position, badge_id in enumerate(normalized):
            db.session.add(ProductBadge(product_id=product_id, badge_id=badge_id, position=str(position)))
        db.session.commit()
        return normalized

    @staticmethod
    def set_product_hashtags(product_id, hashtag_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        normalized = []
        for raw in hashtag_ids:
            hashtag_id = int(raw)
            if db.session.get(Hashtag, hashtag_id) is None:
                raise ValueError(f"hashtag {hashtag_id} not found")
            if hashtag_id not in normalized:
                normalized.append(hashtag_id)
        ProductHashtag.query.filter_by(product_id=product_id).delete()
        for hashtag_id in normalized:
            db.session.add(ProductHashtag(product_id=product_id, hashtag_id=hashtag_id))
        db.session.commit()
        return normalized

    @staticmethod
    def set_product_promotional_strips(product_id, strip_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        normalized = []
        for raw in strip_ids:
            strip_id = int(raw)
            if db.session.get(PromotionalStrip, strip_id) is None:
                raise ValueError(f"promotional strip {strip_id} not found")
            if strip_id not in normalized:
                normalized.append(strip_id)
        ProductPromotionalStrip.query.filter_by(product_id=product_id).delete()
        for position, strip_id in enumerate(normalized):
            db.session.add(ProductPromotionalStrip(product_id=product_id, strip_id=strip_id, sort_order=position))
        db.session.commit()
        return normalized

    @staticmethod
    def set_product_campaigns(product_id, campaign_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        normalized = []
        for raw in campaign_ids:
            campaign_id = int(raw)
            if db.session.get(Campaign, campaign_id) is None:
                raise ValueError(f"campaign {campaign_id} not found")
            if campaign_id not in normalized:
                normalized.append(campaign_id)
        CampaignProduct.query.filter_by(product_id=product_id).delete()
        for position, campaign_id in enumerate(normalized):
            db.session.add(CampaignProduct(product_id=product_id, campaign_id=campaign_id, sort_order=position))
        db.session.commit()
        return normalized

    @staticmethod
    def set_product_categories(product_id, category_ids):
        product = db.session.get(Product, product_id)
        if not product:
            raise LookupError("product not found")
        normalized = []
        for category_id in category_ids:
            cid = int(category_id)
            if db.session.get(Category, cid) is None:
                raise ValueError(f"category {cid} not found")
            if cid not in normalized:
                normalized.append(cid)

        ProductCategory.query.filter_by(product_id=product_id).delete()
        for index, cid in enumerate(normalized):
            db.session.add(ProductCategory(
                product_id=product_id,
                category_id=cid,
                is_primary=(index == 0),
            ))
        db.session.commit()
        return [{"category_id": cid, "is_primary": index == 0} for index, cid in enumerate(normalized)]

    @staticmethod
    def add_option(product_id, payload):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        name = (payload.get("name") or "").strip()
        if not name:
            raise ValueError("option name is required")
        option = ProductOption(
            product_id=product_id,
            name=name,
            option_type=(payload.get("option_type") or "custom").strip(),
            required=bool(payload.get("required", False)),
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(option)
        db.session.flush()

        values = []
        for item in payload.get("values", []):
            label = (item.get("label") or "").strip()
            if not label:
                continue
            value = ProductOptionValue(
                option_id=option.id,
                label=label,
                color_id=item.get("color_id"),
                size_id=item.get("size_id"),
                sort_order=int(item.get("sort_order", 0)),
            )
            db.session.add(value)
            db.session.flush()
            values.append({"id": value.id, "label": value.label})
        db.session.commit()
        return {"id": option.id, "name": option.name, "values": values}

    @staticmethod
    def remove_product_media(product_id, media_id):
        media = db.session.get(ProductMedia, media_id)
        if media is None or media.product_id != product_id:
            raise LookupError("product media not found")
        asset = db.session.get(MediaAsset, media.asset_id)
        db.session.delete(media)
        db.session.flush()
        if asset is not None:
            db.session.delete(asset)
        db.session.commit()
        return {"id": media_id}

    @staticmethod
    def update_variant(product_id, variant_id, payload):
        variant = db.session.get(ProductVariant, variant_id)
        if variant is None or variant.product_id != product_id:
            raise LookupError("variant not found")
        sku = (payload.get("sku") or "").strip().upper()
        if not sku:
            raise ValueError("variant sku is required")
        duplicate = ProductVariant.query.filter(ProductVariant.id != variant_id, ProductVariant.sku == sku).first()
        if duplicate:
            raise ValueError("variant sku already exists")
        color_id = int(payload["color_id"]) if payload.get("color_id") not in (None, "") else None
        size_id = int(payload["size_id"]) if payload.get("size_id") not in (None, "") else None
        color_ref = ProductColorReference.query.filter_by(product_id=product_id, color_id=color_id).first() if color_id else None
        size_ref = ProductSizeReference.query.filter_by(product_id=product_id, size_id=size_id).first() if size_id else None
        if color_id and color_ref is None and color_id != variant.color_id:
            raise ValueError("اختر اللون أولًا ضمن ألوان المنتج.")
        if size_id and size_ref is None and size_id != variant.size_id:
            raise ValueError("اختر المقاس أولًا ضمن مقاسات المنتج.")
        variant.sku = sku
        variant.color_id = color_id
        variant.size_id = size_id
        variant.barcode = (payload.get("barcode") or "").strip() or None
        variant.weight = Decimal(str(payload["weight"])) if payload.get("weight") not in (None, "") else None
        variant.status = (payload.get("status") or variant.status).strip()
        db.session.commit()
        return {"id": variant.id, "sku": variant.sku, "color_id": variant.color_id, "size_id": variant.size_id, "barcode": variant.barcode, "status": variant.status}

    @staticmethod
    def archive_variant(product_id, variant_id):
        variant = db.session.get(ProductVariant, variant_id)
        if variant is None or variant.product_id != product_id:
            raise LookupError("variant not found")
        variant.is_active = False
        variant.status = "archived"
        db.session.commit()
        return {"id": variant.id, "status": variant.status, "is_active": variant.is_active}

    @staticmethod
    def update_option(product_id, option_id, payload):
        option = db.session.get(ProductOption, option_id)
        if option is None or option.product_id != product_id:
            raise LookupError("option not found")
        name = (payload.get("name") or "").strip()
        if not name:
            raise ValueError("option name is required")
        option.name = name
        option.option_type = (payload.get("option_type") or option.option_type).strip()
        option.required = bool(payload.get("required", option.required))
        option.sort_order = int(payload.get("sort_order", option.sort_order))
        for item in payload.get("values", []):
            value_id = item.get("id")
            label = (item.get("label") or "").strip()
            if value_id:
                value = db.session.get(ProductOptionValue, int(value_id))
                if value is None or value.option_id != option.id:
                    raise ValueError("option value not found")
                value.label = label or value.label
                value.color_id = item.get("color_id")
                value.size_id = item.get("size_id")
                value.sort_order = int(item.get("sort_order", value.sort_order))
            elif label:
                db.session.add(ProductOptionValue(option_id=option.id, label=label, color_id=item.get("color_id"), size_id=item.get("size_id"), sort_order=int(item.get("sort_order", 0))))
        db.session.commit()
        return {"id": option.id, "name": option.name, "option_type": option.option_type, "required": option.required}

    @staticmethod
    def remove_option(product_id, option_id):
        option = db.session.get(ProductOption, option_id)
        if option is None or option.product_id != product_id:
            raise LookupError("option not found")
        db.session.delete(option)
        db.session.commit()
        return {"id": option_id}

    @staticmethod
    def add_variant(product_id, payload):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        sku = (payload.get("sku") or "").strip().upper()
        if not sku:
            raise ValueError("variant sku is required")
        if ProductVariant.query.filter_by(sku=sku).first():
            raise ValueError("variant sku already exists")
        color_id = int(payload["color_id"]) if payload.get("color_id") not in (None, "") else None
        size_id = int(payload["size_id"]) if payload.get("size_id") not in (None, "") else None
        selected_color_count = ProductColorReference.query.filter_by(product_id=product_id).count()
        selected_size_count = ProductSizeReference.query.filter_by(product_id=product_id).count()
        if selected_color_count and color_id is None:
            raise ValueError("اختر لونًا من ألوان المنتج أولًا.")
        if selected_size_count and size_id is None:
            raise ValueError("اختر مقاسًا من مقاسات المنتج أولًا.")
        if color_id and ProductColorReference.query.filter_by(product_id=product_id, color_id=color_id).first() is None:
            raise ValueError("اللون المختار غير مرتبط بهذا المنتج.")
        if size_id and ProductSizeReference.query.filter_by(product_id=product_id, size_id=size_id).first() is None:
            raise ValueError("المقاس المختار غير مرتبط بهذا المنتج.")
        variant = ProductVariant(
            product_id=product_id,
            sku=sku,
            color_id=color_id,
            size_id=size_id,
            barcode=(payload.get("barcode") or "").strip() or None,
            weight=Decimal(str(payload["weight"])) if payload.get("weight") not in (None, "") else None,
            status=(payload.get("status") or "active").strip(),
        )
        db.session.add(variant)
        db.session.commit()
        return {
            "id": variant.id,
            "sku": variant.sku,
            "color_id": variant.color_id,
            "size_id": variant.size_id,
            "barcode": variant.barcode,
        }

    @staticmethod
    def set_inventory(product_id, payload):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        variant_id = int(payload.get("variant_id"))
        location_id = int(payload.get("location_id"))
        variant = db.session.get(ProductVariant, variant_id)
        location = db.session.get(InventoryLocation, location_id)
        if variant is None or location is None or variant.product_id != product_id:
            raise ValueError("variant or inventory location is invalid")

        on_hand = int(payload.get("on_hand", 0))
        reserved = int(payload.get("reserved", 0))
        if on_hand < 0 or reserved < 0 or reserved > on_hand:
            raise ValueError("invalid inventory quantities")

        stock = StockInventory.query.filter_by(
            location_id=location_id,
            variant_id=variant_id,
        ).first()
        if stock is None:
            stock = StockInventory(
                location_id=location_id,
                variant_id=variant_id,
                on_hand=on_hand,
                reserved=reserved,
                available=on_hand - reserved,
                reorder_level=int(payload.get("reorder_level", 0)),
            )
            db.session.add(stock)
        else:
            stock.on_hand = on_hand
            stock.reserved = reserved
            stock.available = on_hand - reserved
            stock.reorder_level = int(payload.get("reorder_level", stock.reorder_level))
        db.session.commit()
        return {
            "id": stock.id,
            "variant_id": stock.variant_id,
            "location_id": stock.location_id,
            "on_hand": stock.on_hand,
            "reserved": stock.reserved,
            "available": stock.available,
        }

    @staticmethod
    def create_filter(category_id, payload):
        category = db.session.get(Category, category_id)
        if category is None:
            raise LookupError("category not found")
        name = (payload.get("name") or "").strip()
        if not name:
            raise ValueError("filter name is required")
        row = CategoryFilterDefinition(
            category_id=category_id,
            name=name,
            filter_type=(payload.get("filter_type") or "select").strip(),
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "category_id": row.category_id, "name": row.name, "filter_type": row.filter_type}

    @staticmethod
    def create_filter_value(filter_id, payload):
        filter_row = db.session.get(CategoryFilterDefinition, filter_id)
        if filter_row is None:
            raise LookupError("filter not found")
        label = (payload.get("label") or "").strip()
        slug = (payload.get("slug") or "").strip().lower()
        if not label or not slug:
            raise ValueError("label and slug are required")
        duplicate = CategoryFilterValue.query.filter_by(filter_id=filter_id, slug=slug).first()
        if duplicate:
            raise ValueError("filter value slug already exists")
        row = CategoryFilterValue(
            filter_id=filter_id,
            label=label,
            slug=slug,
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "filter_id": row.filter_id, "label": row.label, "slug": row.slug}

    @staticmethod
    def set_product_filter_values(product_id, value_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        normalized = []
        for raw in value_ids:
            value_id = int(raw)
            if db.session.get(CategoryFilterValue, value_id) is None:
                raise ValueError(f"filter value {value_id} not found")
            if value_id not in normalized:
                normalized.append(value_id)
        ProductFilterValue.query.filter_by(product_id=product_id).delete()
        for value_id in normalized:
            db.session.add(ProductFilterValue(product_id=product_id, filter_value_id=value_id))
        db.session.commit()
        return [{"product_id": product_id, "filter_value_id": value_id} for value_id in normalized]
    
    @staticmethod
    def category_filters(category_id):
        rows = CategoryFilterDefinition.query.filter_by(
            category_id=category_id, is_active=True
        ).order_by(CategoryFilterDefinition.sort_order, CategoryFilterDefinition.id).all()
        return [
            {
                "id": row.id,
                "name": row.name,
                "filter_type": row.filter_type,
                "values": [
                    {
                        "id": value.id,
                        "label": value.label,
                        "slug": value.slug,
                        "sort_order": value.sort_order,
                    }
                    for value in CategoryFilterValue.query.filter_by(filter_id=row.id, is_active=True).order_by(CategoryFilterValue.sort_order, CategoryFilterValue.id).all()
                ],
            }
            for row in rows
        ]

    @staticmethod
    def set_display_settings(product_id, payload):
        product = db.session.get(Product, product_id)
        if product is None:
            raise LookupError("product not found")
        settings = db.session.get(ProductDisplaySettings, product_id)
        if settings is None:
            settings = ProductDisplaySettings(product_id=product_id)
            db.session.add(settings)
        for field in (
            "show_rating", "show_sold_badge", "show_shipping_banner",
            "show_return", "show_review_count",
        ):
            if field in payload:
                setattr(settings, field, bool(payload[field]))
        if "card_aspect_ratio" in payload:
            settings.card_aspect_ratio = str(payload["card_aspect_ratio"])
        if "card_radius" in payload:
            settings.card_radius = max(0, int(payload["card_radius"]))
        db.session.commit()
        return {
            "product_id": product_id,
            "show_rating": settings.show_rating,
            "show_sold_badge": settings.show_sold_badge,
            "show_shipping_banner": settings.show_shipping_banner,
            "show_return": settings.show_return,
            "show_review_count": settings.show_review_count,
            "card_aspect_ratio": settings.card_aspect_ratio,
            "card_radius": settings.card_radius,
        }

    @staticmethod
    def set_policies(product_id, payload):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        policy = db.session.get(ProductPolicyAssignment, product_id)
        if policy is None:
            policy = ProductPolicyAssignment(product_id=product_id)
            db.session.add(policy)
        mappings = (
            ("shipping_policy_id", ShippingPolicy),
            ("return_policy_id", ReturnPolicy),
            ("warranty_policy_id", WarrantyPolicy),
        )
        for field, model in mappings:
            if field in payload:
                if payload[field] in (None, ""):
                    setattr(policy, field, None)
                else:
                    if db.session.get(model, int(payload[field])) is None:
                        raise ValueError(f"{field} not found")
                    setattr(policy, field, int(payload[field]))
        db.session.commit()
        return {
            "product_id": product_id,
            "shipping_policy_id": policy.shipping_policy_id,
            "return_policy_id": policy.return_policy_id,
            "warranty_policy_id": policy.warranty_policy_id,
        }

    @staticmethod
    def create_inventory_location(payload):
        name = (payload.get("name") or "").strip()
        code = (payload.get("code") or "").strip().upper()
        if not name or not code:
            raise ValueError("name and code are required")
        if InventoryLocation.query.filter_by(code=code).first():
            raise ValueError("location code already exists")
        location = InventoryLocation(name=name, code=code, city_id=payload.get("city_id"))
        db.session.add(location)
        db.session.commit()
        return {"id": location.id, "name": location.name, "code": location.code, "city_id": location.city_id}

    @staticmethod
    def list_inventory_locations():
        return [
            {"id": x.id, "name": x.name, "code": x.code, "city_id": x.city_id}
            for x in InventoryLocation.query.filter_by(is_active=True).order_by(InventoryLocation.name).all()
        ]

    @staticmethod
    def option_references(product_id=None):
        from ...models import Size

        current_color_ids = set()
        current_size_ids = set()
        if product_id:
            current_color_ids = {
                int(x)
                for (x,) in db.session.query(ProductVariant.color_id)
                .filter(ProductVariant.product_id == int(product_id), ProductVariant.color_id.isnot(None))
                .all()
            }
            current_size_ids = {
                int(x)
                for (x,) in db.session.query(ProductVariant.size_id)
                .filter(ProductVariant.product_id == int(product_id), ProductVariant.size_id.isnot(None))
                .all()
            }

        colors = (
            Color.query
            .filter(or_(Color.is_active.is_(True), Color.id.in_(current_color_ids) if current_color_ids else False))
            .order_by(Color.is_active.desc(), Color.sort_order, Color.name)
            .all()
        )
        sizes = (
            Size.query
            .filter(or_(Size.is_active.is_(True), Size.id.in_(current_size_ids) if current_size_ids else False))
            .order_by(Size.is_active.desc(), Size.group, Size.sort_order, Size.label)
            .all()
        )
        return {
            "colors": [
                {
                    "id": x.id,
                    "name": x.name,
                    "hex_code": x.hex_code,
                    "swatch_asset_id": x.swatch_asset_id,
                    "is_active": bool(x.is_active),
                }
                for x in colors
            ],
            "sizes": [
                {
                    "id": x.id,
                    "group": x.group,
                    "code": x.code,
                    "label": x.label,
                    "is_active": bool(x.is_active),
                }
                for x in sizes
            ],
        }

    @staticmethod
    def product_reference_data(product_id=None):
        product = db.session.get(Product, int(product_id)) if product_id else None
        if product_id and product is None:
            raise LookupError("product not found")

        current_category_ids = {int(x.category_id) for x in ProductCategory.query.filter_by(product_id=product_id).all()} if product_id else set()
        current_badge_ids = {int(x.badge_id) for x in ProductBadge.query.filter_by(product_id=product_id).all()} if product_id else set()
        current_hashtag_ids = {int(x.hashtag_id) for x in ProductHashtag.query.filter_by(product_id=product_id).all()} if product_id else set()
        current_strip_ids = {int(x.strip_id) for x in ProductPromotionalStrip.query.filter_by(product_id=product_id).all()} if product_id else set()
        current_campaign_ids = {int(x.campaign_id) for x in CampaignProduct.query.filter_by(product_id=product_id).all()} if product_id else set()
        current_side_circle_ids = set(CatalogService.list_product_side_category_circles(product_id)) if product_id else set()
        current_color_ids = {int(x.color_id) for x in ProductColorReference.query.filter_by(product_id=product_id).all()} if product_id else set()
        current_size_ids = {int(x.size_id) for x in ProductSizeReference.query.filter_by(product_id=product_id).all()} if product_id else set()

        # Products created before product-level dimension references are backfilled
        # from their variants the first time this endpoint is read.
        if product_id and not current_color_ids:
            current_color_ids = {
                int(x)
                for (x,) in db.session.query(ProductVariant.color_id)
                .filter(ProductVariant.product_id == int(product_id), ProductVariant.color_id.isnot(None))
                .all()
            }
        if product_id and not current_size_ids:
            current_size_ids = {
                int(x)
                for (x,) in db.session.query(ProductVariant.size_id)
                .filter(ProductVariant.product_id == int(product_id), ProductVariant.size_id.isnot(None))
                .all()
            }

        def active_or_current(model, ids, order_by):
            condition = or_(model.is_active.is_(True), model.id.in_(ids) if ids else False)
            return model.query.filter(condition).order_by(*order_by).all()

        categories = active_or_current(Category, current_category_ids, (Category.parent_id, Category.sort_order, Category.name))
        brands = active_or_current(Brand, {product.brand_id} if product and product.brand_id else set(), (Brand.name,))
        badges = active_or_current(Badge, current_badge_ids, (Badge.priority.desc(), Badge.name))
        hashtags = active_or_current(Hashtag, current_hashtag_ids, (Hashtag.sort_order, Hashtag.name))
        strips = active_or_current(PromotionalStrip, current_strip_ids, (PromotionalStrip.id.desc(),))
        campaigns = active_or_current(Campaign, current_campaign_ids, (Campaign.display_priority.desc(), Campaign.name))
        side_circles = (
            SideCategoryCircle.query
            .filter(or_(
                SideCategoryCircle.is_active.is_(True),
                SideCategoryCircle.id.in_(current_side_circle_ids) if current_side_circle_ids else False,
            ))
            .order_by(SideCategoryCircle.side_category_id, SideCategoryCircle.sort_order, SideCategoryCircle.name)
            .all()
        )
        colors = active_or_current(Color, current_color_ids, (Color.sort_order, Color.name))

        from ...models import Size
        sizes = active_or_current(Size, current_size_ids, (Size.group, Size.sort_order, Size.label))

        assignment = db.session.get(ProductPolicyAssignment, int(product_id)) if product_id else None
        policy_specs = (
            ("shipping", ShippingPolicy, assignment.shipping_policy_id if assignment else None),
            ("return", ReturnPolicy, assignment.return_policy_id if assignment else None),
            ("warranty", WarrantyPolicy, assignment.warranty_policy_id if assignment else None),
        )
        policies = {}
        for key, model, current_id in policy_specs:
            ids = {int(current_id)} if current_id else set()
            rows = active_or_current(model, ids, (model.name,))
            policies[key] = [
                {
                    "id": row.id,
                    "name": row.name,
                    "is_active": bool(row.is_active),
                    "summary": (
                        row.delivery_window if key == "shipping"
                        else f"{row.return_window_days} يوم" if key == "return"
                        else f"{row.duration_days} يوم"
                    ),
                }
                for row in rows
            ]

        size_guides = SizeGuide.query.filter_by(is_active=True).order_by(SizeGuide.name).all()
        return {
            "categories": [
                {
                    "id": row.id, "name": row.name, "slug": row.slug,
                    "parent_id": row.parent_id, "is_active": bool(row.is_active),
                }
                for row in categories
            ],
            "colors": [
                {
                    "id": row.id, "name": row.name, "hex_code": row.hex_code,
                    "swatch_asset_id": row.swatch_asset_id, "is_active": bool(row.is_active),
                    "selected": row.id in current_color_ids,
                }
                for row in colors
            ],
            "sizes": [
                {
                    "id": row.id, "group": row.group, "code": row.code, "label": row.label,
                    "is_active": bool(row.is_active), "selected": row.id in current_size_ids,
                }
                for row in sizes
            ],
            "brands": [
                {
                    "id": row.id, "name": row.name, "slug": row.slug,
                    "logo_asset_id": row.logo_asset_id, "is_active": bool(row.is_active),
                }
                for row in brands
            ],
            "badges": [
                {
                    "id": row.id, "name": row.name, "code": row.code,
                    "bg_color": row.bg_color, "text_color": row.text_color,
                    "style": row.style, "priority": row.priority, "is_active": bool(row.is_active),
                }
                for row in badges
            ],
            "hashtags": [
                {
                    "id": row.id, "name": row.name, "slug": row.slug,
                    "display_name": row.display_name, "is_active": bool(row.is_active),
                }
                for row in hashtags
            ],
            "promotional_strips": [
                {
                    "id": row.id, "name": row.name, "text_prefix": row.text_prefix,
                    "text_body": row.text_body, "background_color": row.background_color,
                    "text_color": row.text_color, "is_active": bool(row.is_active),
                }
                for row in strips
            ],
            "campaigns": [
                {
                    "id": row.id, "name": row.name, "slug": row.slug,
                    "status": row.status, "display_priority": row.display_priority,
                    "badge_id": row.badge_id, "is_active": bool(row.is_active),
                }
                for row in campaigns
            ],
            "side_categories": CatalogService.list_side_categories(include_archived=False),
            "selected_side_category_circle_ids": sorted(current_side_circle_ids),
            "policies": policies,
            "size_guides": [
                {"id": row.id, "name": row.name, "guide_type": row.guide_type, "fit_type": row.fit_type}
                for row in size_guides
            ],
        }

    @staticmethod
    def publish_product(product_id):
        product = db.session.get(Product, product_id)
        if not product:
            raise LookupError("product not found")
        category_count = ProductCategory.query.filter_by(product_id=product_id).count()
        variant_count = ProductVariant.query.filter_by(product_id=product_id, is_active=True).count()
        media_count = ProductMedia.query.filter_by(product_id=product_id).count()
        errors = []
        if not product.name:
            errors.append("name")
        if product.base_price is None or product.base_price < 0:
            errors.append("base_price")
        if category_count == 0:
            errors.append("category")
        if variant_count == 0:
            errors.append("variant")
        if media_count == 0:
            errors.append("media")
        if errors:
            raise ValueError("missing publish requirements: " + ", ".join(errors))
        product.status = "published"
        product.published_at = db.func.now()
        db.session.commit()
        return CatalogService._serialize_product(product)

    @staticmethod
    def wizard_snapshot(product_id):
        product = db.session.get(Product, product_id)
        if not product:
            raise LookupError("product not found")
        categories = [
            CatalogService._serialize_category(x)
            for x in Category.query
            .join(ProductCategory, ProductCategory.category_id == Category.id)
            .filter(ProductCategory.product_id == product_id)
            .order_by(ProductCategory.is_primary.desc(), Category.sort_order, Category.name)
            .all()
        ]
        options = []
        for option in ProductOption.query.filter_by(product_id=product_id).order_by(ProductOption.sort_order, ProductOption.id):
            values = ProductOptionValue.query.filter_by(option_id=option.id).order_by(ProductOptionValue.sort_order, ProductOptionValue.id).all()
            options.append({
                "id": option.id,
                "name": option.name,
                "option_type": option.option_type,
                "required": option.required,
                "values": [{"id": value.id, "label": value.label, "color_id": value.color_id, "size_id": value.size_id} for value in values],
            })
        variants = [
            {
                "id": variant.id,
                "sku": variant.sku,
                "color_id": variant.color_id,
                "size_id": variant.size_id,
                "barcode": variant.barcode,
                "weight": str(variant.weight) if variant.weight is not None else None,
                "status": variant.status,
            }
            for variant in ProductVariant.query.filter_by(product_id=product_id).order_by(ProductVariant.id).all()
        ]
        badges = [
            {"id": row.badge_id}
            for row in ProductBadge.query.filter_by(product_id=product_id).order_by(ProductBadge.position, ProductBadge.id).all()
        ]
        hashtags = [
            {"id": row.hashtag_id}
            for row in ProductHashtag.query.filter_by(product_id=product_id).order_by(ProductHashtag.id).all()
        ]
        promotional_strips = [
            {"id": row.strip_id}
            for row in ProductPromotionalStrip.query.filter_by(product_id=product_id).order_by(ProductPromotionalStrip.sort_order, ProductPromotionalStrip.id).all()
        ]
        campaigns = [
            {"id": row.campaign_id}
            for row in CampaignProduct.query.filter_by(product_id=product_id).order_by(CampaignProduct.sort_order, CampaignProduct.id).all()
        ]
        media_rows = (
            db.session.query(ProductMedia, MediaAsset, Color)
            .join(MediaAsset, MediaAsset.id == ProductMedia.asset_id)
            .outerjoin(Color, Color.id == ProductMedia.color_id)
            .filter(ProductMedia.product_id == product_id)
            .order_by(ProductMedia.sort_order, ProductMedia.id)
            .all()
        )
        media = [
            {
                "id": media_row.id,
                "asset_id": media_row.asset_id,
                "url": asset.url,
                "role": media_row.role,
                "sort_order": media_row.sort_order,
                "color_id": media_row.color_id,
                "color_name": color.name if color else None,
                "color_hex": color.hex_code if color else None,
            }
            for media_row, asset, color in media_rows
        ]
        reference_colors = [
            {"id": row.color_id}
            for row in ProductColorReference.query.filter_by(product_id=product_id).order_by(ProductColorReference.sort_order, ProductColorReference.id).all()
        ]
        reference_sizes = [
            {"id": row.size_id}
            for row in ProductSizeReference.query.filter_by(product_id=product_id).order_by(ProductSizeReference.sort_order, ProductSizeReference.id).all()
        ]
        side_category_circle_ids = [
            {"id": circle_id}
            for circle_id in CatalogService.list_product_side_category_circles(product_id)
        ]

        inventory = [
            {
                "id": stock.id,
                "variant_id": stock.variant_id,
                "location_id": stock.location_id,
                "on_hand": stock.on_hand,
                "reserved": stock.reserved,
                "available": stock.available,
                "reorder_level": stock.reorder_level,
            }
            for stock in StockInventory.query
            .join(ProductVariant, ProductVariant.id == StockInventory.variant_id)
            .filter(ProductVariant.product_id == product_id)
            .order_by(StockInventory.location_id, StockInventory.variant_id)
            .all()
        ]
        display = db.session.get(ProductDisplaySettings, product_id)
        policies = db.session.get(ProductPolicyAssignment, product_id)
        return {
            "product": CatalogService._serialize_product(product),
            "categories": categories,
            "options": options,
            "variants": variants,
            "media": media,
            "badges": badges,
            "hashtags": hashtags,
            "promotional_strips": promotional_strips,
            "campaigns": campaigns,
            "reference_colors": reference_colors,
            "reference_sizes": reference_sizes,
            "side_category_circles": side_category_circle_ids,
            "inventory": inventory,
            "locations": CatalogService.list_inventory_locations(),
            "display": {
                "show_rating": display.show_rating if display else True,
                "show_sold_badge": display.show_sold_badge if display else True,
                "show_shipping_banner": display.show_shipping_banner if display else True,
                "show_return": display.show_return if display else True,
                "show_review_count": display.show_review_count if display else True,
            },
            "policies": {
                "shipping_policy_id": policies.shipping_policy_id if policies else None,
                "return_policy_id": policies.return_policy_id if policies else None,
                "warranty_policy_id": policies.warranty_policy_id if policies else None,
            },
            "publishable": bool(categories and variants and media),
            "steps": {
                "basics": True,
                "categories": bool(categories),
                "media": bool(media),
                "options": bool(reference_colors or reference_sizes or options),
                "variants": bool(variants),
                "inventory": bool(inventory),
                "publish": bool(categories and variants and media),
            },
        }


    @staticmethod
    def validate_trend_product_selection(hashtag_id, product_ids):
        hashtag = db.session.get(Hashtag, int(hashtag_id))
        if hashtag is None:
            raise ValueError("الهاشتاج المختار غير موجود.")
        if not hashtag.is_active:
            raise ValueError("لا يمكن ربط ترند بهاشتاج مؤرشف.")

        normalized = []
        for raw in product_ids or []:
            product_id = int(raw)
            if product_id not in normalized:
                normalized.append(product_id)
        if len(normalized) != 3:
            raise ValueError("يجب اختيار 3 منتجات للترند بالضبط.")

        products = Product.query.filter(
            Product.id.in_(normalized),
            Product.is_active.is_(True),
            Product.status == "published",
        ).all()
        if len(products) != 3:
            raise ValueError("يجب أن تكون المنتجات الثلاثة منشورة ونشطة.")

        linked_ids = {
            product_id
            for (product_id,) in db.session.query(ProductHashtag.product_id)
            .filter(
                ProductHashtag.hashtag_id == hashtag.id,
                ProductHashtag.product_id.in_(normalized),
            )
            .all()
        }
        if any(product_id not in linked_ids for product_id in normalized):
            raise ValueError("كل المنتجات المختارة يجب أن تكون مرتبطة بالهاشتاج الرئيسي.")
        return normalized

    @staticmethod
    def set_trend_products(trend_id, hashtag_id, product_ids):
        trend = db.session.get(Trend, trend_id)
        if trend is None:
            raise LookupError("trend not found")

        normalized = CatalogService.validate_trend_product_selection(hashtag_id, product_ids)
        TrendProduct.query.filter_by(trend_id=trend.id).delete()
        for slot, product_id in enumerate(normalized):
            db.session.add(TrendProduct(
                trend_id=trend.id,
                product_id=product_id,
                slot=slot,
            ))
        db.session.commit()
        return normalized

    @staticmethod
    def trend_product_candidates(hashtag_id, limit=100):
        hashtag = db.session.get(Hashtag, int(hashtag_id))
        if hashtag is None:
            raise LookupError("hashtag not found")

        products = (
            Product.query
            .join(ProductHashtag, ProductHashtag.product_id == Product.id)
            .filter(
                ProductHashtag.hashtag_id == hashtag.id,
                Product.is_active.is_(True),
                Product.status == "published",
            )
            .order_by(Product.id.desc())
            .limit(min(max(int(limit), 1), 200))
            .all()
        )
        items = []
        for product in products:
            media = (
                db.session.query(MediaAsset)
                .join(ProductMedia, ProductMedia.asset_id == MediaAsset.id)
                .filter(ProductMedia.product_id == product.id)
                .order_by(ProductMedia.sort_order, ProductMedia.id)
                .first()
            )
            brand = db.session.get(Brand, product.brand_id) if product.brand_id else None
            items.append({
                "id": product.id,
                "sku": product.sku,
                "name": product.name,
                "slug": product.slug,
                "price": str(product.base_price),
                "compare_at_price": str(product.compare_at_price) if product.compare_at_price is not None else None,
                "brand": {
                    "id": brand.id,
                    "name": brand.name,
                } if brand else None,
                "image_url": media.url if media else None,
            })
        return items

    @staticmethod
    def _serialize_trend_product(product):
        media = (
            db.session.query(MediaAsset)
            .join(ProductMedia, ProductMedia.asset_id == MediaAsset.id)
            .filter(ProductMedia.product_id == product.id)
            .order_by(ProductMedia.sort_order, ProductMedia.id)
            .first()
        )
        brand = db.session.get(Brand, product.brand_id) if product.brand_id else None
        return {
            "id": product.id,
            "sku": product.sku,
            "name": product.name,
            "slug": product.slug,
            "price": str(product.base_price),
            "compare_at_price": str(product.compare_at_price) if product.compare_at_price is not None else None,
            "brand": {
                "id": brand.id,
                "name": brand.name,
            } if brand else None,
            "image_url": media.url if media else None,
        }

    @staticmethod
    def _trend_timer_seconds(trend):
        if not trend.timer_value:
            return None
        return int(trend.timer_value * 60) if trend.timer_unit == "minutes" else int(trend.timer_value)

    @staticmethod
    def is_trend_timer_expired(trend, now=None):
        seconds = CatalogService._trend_timer_seconds(trend)
        if not seconds or not trend.timer_started_at:
            return False
        now = now or datetime.now(timezone.utc)
        started = trend.timer_started_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=timezone.utc)
        return now >= started + timedelta(seconds=seconds)

    @staticmethod
    def serialize_public_trend(trend):
        hashtag = db.session.get(Hashtag, trend.hashtag_id)
        background = db.session.get(MediaAsset, trend.background_asset_id)
        assignments = (
            TrendProduct.query
            .filter_by(trend_id=trend.id)
            .order_by(TrendProduct.slot, TrendProduct.id)
            .all()
        )
        products = []
        for assignment in assignments:
            product = db.session.get(Product, assignment.product_id)
            if not product or not product.is_active or product.status != "published":
                continue
            products.append({
                "slot": assignment.slot,
                "product": CatalogService._serialize_trend_product(product),
            })
        return {
            "id": trend.id,
            "expired": CatalogService.is_trend_timer_expired(trend),
            "hashtag": {
                "id": hashtag.id,
                "name": hashtag.name,
                "slug": hashtag.slug,
                "display_name": hashtag.display_name or f"#{hashtag.name}",
            } if hashtag else None,
            "promo_text": trend.promo_text,
            "duration_days": trend.duration_days,
            "timer": {
                "enabled": bool(trend.timer_value),
                "value": trend.timer_value,
                "unit": trend.timer_unit,
                "seconds": (trend.timer_value * 60 if trend.timer_value and trend.timer_unit == "minutes" else trend.timer_value),
                "started_at": trend.timer_started_at.isoformat() if trend.timer_started_at else None,
                "ends_at": (
                    (trend.timer_started_at + timedelta(
                        seconds=(trend.timer_value * 60 if trend.timer_unit == "minutes" else trend.timer_value)
                    )).isoformat()
                    if trend.timer_started_at and trend.timer_value else None
                ),
            },
            "overlay": {
                "text": trend.overlay_text,
                "text_color": trend.overlay_text_color,
                "background_color": trend.overlay_background_color,
            },
            "status": trend.status,
            "background": {
                "id": background.id,
                "url": background.url,
                "width": background.width,
                "height": background.height,
            } if background else None,
            "products": products,
        }

    @staticmethod
    def list_public_trends(limit=20):
        rows = (
            Trend.query
            .filter(
                Trend.is_active.is_(True),
                Trend.status == "active",
            )
            .order_by(Trend.sort_order, Trend.id.desc())
            .limit(min(max(int(limit), 1), 50))
            .all()
        )
        items = []
        for trend in rows:
            if CatalogService.is_trend_timer_expired(trend):
                continue
            payload = CatalogService.serialize_public_trend(trend)
            if payload["hashtag"] and payload["background"] and len(payload["products"]) == 3:
                items.append(payload)
        return items


class MediaService:
    @staticmethod
    def save_generic_files(files, owner_folder):
        root = Path(current_app.config["MEDIA_ROOT"])
        root.mkdir(parents=True, exist_ok=True)
        results = []
        for incoming in files:
            if not incoming or not incoming.filename:
                continue
            asset_id = uuid4().hex
            original = incoming.filename
            suffix = Path(original).suffix.lower()[:12]
            try:
                incoming.stream.seek(0)
                is_image = (incoming.mimetype or "").startswith("image/")
                if is_image:
                    image = ImageOps.exif_transpose(Image.open(incoming.stream))
                    if image.mode not in ("RGB", "RGBA"):
                        image = image.convert("RGBA" if "transparency" in image.info else "RGB")
                    image.thumbnail((current_app.config["MEDIA_MAX_SIDE"], current_app.config["MEDIA_MAX_SIDE"]), Image.Resampling.LANCZOS)
                    if image.mode == "RGBA":
                        background = Image.new("RGB", image.size, "white")
                        background.paste(image, mask=image.getchannel("A"))
                        image = background
                    rel_path = f"{owner_folder}/{asset_id}.webp"
                    out_path = root / rel_path
                    out_path.parent.mkdir(parents=True, exist_ok=True)
                    image.save(out_path, "WEBP", quality=current_app.config["MEDIA_WEBP_QUALITY"], method=6)
                    mime_type = "image/webp"
                    width, height = image.width, image.height
                else:
                    rel_path = f"{owner_folder}/{asset_id}{suffix}"
                    out_path = root / rel_path
                    out_path.parent.mkdir(parents=True, exist_ok=True)
                    incoming.save(out_path)
                    mime_type = incoming.mimetype or "application/octet-stream"
                    width = height = None

                asset = MediaAsset(
                    storage_key=rel_path,
                    url=f"{current_app.config.get('MEDIA_BASE_URL', '/media')}/{rel_path}",
                    mime_type=mime_type,
                    width=width,
                    height=height,
                    size_bytes=out_path.stat().st_size,
                    metadata_json={"source_name": original},
                )
                db.session.add(asset)
                db.session.flush()
                results.append({
                    "id": asset.id,
                    "url": asset.url,
                    "mime_type": asset.mime_type,
                    "width": asset.width,
                    "height": asset.height,
                    "size_bytes": asset.size_bytes,
                })
            except Exception as exc:
                db.session.rollback()
                raise ValueError(f"file processing failed: {exc}") from exc
        db.session.commit()
        return results

    @staticmethod
    def attach_product_files(product_id, files, color_id=None):
        product = db.session.get(Product, product_id)
        if product is None:
            raise LookupError("product not found")
        if not files:
            raise ValueError("at least one file is required")

        root = Path(current_app.config["MEDIA_ROOT"])
        root.mkdir(parents=True, exist_ok=True)
        max_side = int(current_app.config.get("MEDIA_MAX_SIDE", 1600))
        quality = int(current_app.config.get("MEDIA_WEBP_QUALITY", 82))
        items = []

        for incoming in files:
            if not incoming or not incoming.filename:
                continue
            try:
                incoming.stream.seek(0)
                image = Image.open(incoming.stream)
                image = ImageOps.exif_transpose(image)
                if image.mode not in ("RGB", "RGBA"):
                    image = image.convert("RGBA" if "transparency" in image.info else "RGB")
                image.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)

                if image.mode == "RGBA":
                    background = Image.new("RGB", image.size, "white")
                    background.paste(image, mask=image.getchannel("A"))
                    image = background

                asset_id = uuid4().hex
                rel_path = f"products/{product_id}/{asset_id}.webp"
                out_path = root / rel_path
                out_path.parent.mkdir(parents=True, exist_ok=True)
                image.save(out_path, "WEBP", quality=quality, method=6)

                asset = MediaAsset(
                    storage_key=rel_path,
                    url=f"{current_app.config.get('MEDIA_BASE_URL', '/media')}/{rel_path}",
                    mime_type="image/webp",
                    width=image.width,
                    height=image.height,
                    size_bytes=out_path.stat().st_size,
                    metadata_json={"source_name": incoming.filename},
                )
                db.session.add(asset)
                db.session.flush()

                media = ProductMedia(
                    product_id=product_id,
                    asset_id=asset.id,
                    color_id=int(color_id) if color_id not in (None, "", 0, "0") else None,
                    role="gallery",
                    sort_order=len(items),
                )
                db.session.add(media)
                items.append({
                    "media_id": media.id,
                    "asset_id": asset.id,
                    "url": asset.url,
                    "width": asset.width,
                    "height": asset.height,
                    "size_bytes": asset.size_bytes,
                })
            except Exception as exc:
                db.session.rollback()
                raise ValueError(f"image processing failed: {exc}") from exc

        db.session.commit()
        return items
