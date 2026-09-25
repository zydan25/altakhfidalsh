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
    def create_category(payload):
        name = (payload.get("name") or "").strip()
        slug = (payload.get("slug") or "").strip().lower()
        parent_id = payload.get("parent_id")
        if not name or not slug:
            raise ValueError("name and slug are required")
        if parent_id is not None and not db.session.get(Category, int(parent_id)):
            raise ValueError("parent category was not found")
        if Category.query.filter_by(parent_id=parent_id, slug=slug).first():
            raise ValueError("slug already exists at this level")

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

    def add_variant(product_id, payload):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        sku = (payload.get("sku") or "").strip().upper()
        if not sku:
            raise ValueError("variant sku is required")
        if ProductVariant.query.filter_by(sku=sku).first():
            raise ValueError("variant sku already exists")
        variant = ProductVariant(
            product_id=product_id,
            sku=sku,
            color_id=payload.get("color_id"),
            size_id=payload.get("size_id"),
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
            if field in payload and payload[field] is not None:
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
    def option_references():
        from ...models import Size
        return {
            "colors": [
                {"id": x.id, "name": x.name, "hex_code": x.hex_code, "swatch_asset_id": x.swatch_asset_id}
                for x in Color.query.filter_by(is_active=True).order_by(Color.sort_order, Color.name).all()
            ],
            "sizes": [
                {"id": x.id, "group": x.group, "code": x.code, "label": x.label}
                for x in Size.query.filter_by(is_active=True).order_by(Size.sort_order, Size.label).all()
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
        media = [
            {"id": media.id, "asset_id": media.asset_id, "role": media.role, "sort_order": media.sort_order}
            for media in ProductMedia.query.filter_by(product_id=product_id).order_by(ProductMedia.sort_order, ProductMedia.id).all()
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
                "options": bool(options),
                "variants": bool(variants),
                "inventory": bool(inventory),
                "publish": bool(categories and variants and media),
            },
        }


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
