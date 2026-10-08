from datetime import datetime, timedelta, timezone
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from uuid import uuid4
import re

from PIL import Image, ImageOps
from flask import current_app
from sqlalchemy import or_

from ...extensions import db
from ...services.pricing import calculate_customer_price, price_for_customer
from ...models import (
    Category,
    CategoryHomeDisplaySetting,
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
    SideCircleDisplaySetting,
    SideCircleDisplayGroup,
    SideCircleDisplayGroupItem,
    ProductSideCategoryCircle,
    SizeGuide,
    Size,
    ProductColorReference,
    ProductSizeReference,
    ProductSizeGuideReference,
    AppSetting,
    Review,
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
        icon = db.session.get(MediaAsset, category.icon_asset_id) if category.icon_asset_id else None
        return {
            "id": category.id,
            "parent_id": category.parent_id,
            "name": category.name,
            "slug": category.slug,
            "display_style": category.display_style,
            "icon_asset_id": category.icon_asset_id,
            "icon_url": icon.url if icon else None,
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
    def default_home_category_display():
        return {
            "grid_rows": 2,
            "show_coupon_strip": True,
            "show_looks_strip": True,
            "item_shape": "circle",
            "item_size": 64,
            "item_width": 64,
            "item_height": 64,
            "item_spacing": 6,
            "item_corner_radius": 16,
            "item_label_font_size": 9,
            "item_label_bold": True,
        }

    @staticmethod
    def serialize_home_category_display(setting=None):
        values = CatalogService.default_home_category_display()
        if setting is not None:
            values.update({
                "grid_rows": int(setting.grid_rows),
                "show_coupon_strip": bool(setting.show_coupon_strip),
                "show_looks_strip": bool(setting.show_looks_strip),
                "item_shape": setting.item_shape,
                "item_size": int(setting.item_size),
                "item_width": int(getattr(setting, "item_width", setting.item_size)),
                "item_height": int(getattr(setting, "item_height", setting.item_size)),
                "item_spacing": int(setting.item_spacing),
                "item_corner_radius": int(setting.item_corner_radius),
                "item_label_font_size": int(setting.item_label_font_size),
                "item_label_bold": bool(setting.item_label_bold),
            })
        return values

    @staticmethod
    def list_home_category_display():
        settings = CategoryHomeDisplaySetting.query.order_by(
            CategoryHomeDisplaySetting.category_id.is_(None).desc(),
            CategoryHomeDisplaySetting.category_id,
        ).all()
        return {
            "all": CatalogService.serialize_home_category_display(
                next((x for x in settings if x.category_id is None), None)
            ),
            "categories": {
                str(x.category_id): CatalogService.serialize_home_category_display(x)
                for x in settings
                if x.category_id is not None
            },
        }

    @staticmethod
    def get_home_category_display(category_id=None):
        settings = CategoryHomeDisplaySetting.query
        if category_id is None:
            setting = settings.filter(CategoryHomeDisplaySetting.category_id.is_(None)).first()
            return CatalogService.serialize_home_category_display(setting)
        setting = settings.filter(
            CategoryHomeDisplaySetting.category_id == int(category_id)
        ).first()
        if setting is not None:
            return CatalogService.serialize_home_category_display(setting)
        global_setting = CategoryHomeDisplaySetting.query.filter(
            CategoryHomeDisplaySetting.category_id.is_(None)
        ).first()
        return CatalogService.serialize_home_category_display(global_setting)

    @staticmethod
    def save_home_category_display(category_id, payload):
        normalized_category_id = None if category_id in (None, "", 0, "0", -1, "-1") else int(category_id)
        category = (
            db.session.get(Category, normalized_category_id)
            if normalized_category_id is not None
            else None
        )
        if normalized_category_id is not None and (
            category is None or not category.is_active or category.parent_id is not None
        ):
            raise ValueError("إعدادات الدوائر يجب أن ترتبط بفئة رئيسية نشطة.")

        grid_rows = max(1, min(6, int(payload.get("grid_rows", 2))))
        legacy_size = max(42, min(110, int(payload.get("item_size", 64))))
        item_width = max(42, min(240, int(payload.get("item_width", legacy_size))))
        item_height = max(42, min(240, int(payload.get("item_height", legacy_size))))
        item_size = min(110, item_width, item_height)
        item_spacing = max(0, min(24, int(payload.get("item_spacing", 6))))
        item_corner_radius = max(0, min(100, int(payload.get("item_corner_radius", 16))))
        item_label_font_size = max(7, min(24, int(payload.get("item_label_font_size", 9))))
        item_label_bold = bool(payload.get("item_label_bold", True))
        item_shape = str(payload.get("item_shape", "circle")).strip().lower()
        if item_shape not in {"circle", "rounded", "square"}:
            raise ValueError("شكل الفئات غير صالح.")
        show_coupon_strip = bool(payload.get("show_coupon_strip", True))
        show_looks_strip = bool(payload.get("show_looks_strip", True))

        scope_key = "all" if normalized_category_id is None else f"category:{normalized_category_id}"
        setting = CategoryHomeDisplaySetting.query.filter_by(scope_key=scope_key).first()
        if setting is None:
            setting = CategoryHomeDisplaySetting(
                scope_key=scope_key,
                category_id=normalized_category_id,
            )
            db.session.add(setting)

        setting.grid_rows = grid_rows
        setting.show_coupon_strip = show_coupon_strip
        setting.show_looks_strip = show_looks_strip
        setting.item_shape = item_shape
        setting.item_size = item_size
        setting.item_width = item_width
        setting.item_height = item_height
        setting.item_spacing = item_spacing
        setting.item_corner_radius = item_corner_radius
        setting.item_label_font_size = item_label_font_size
        setting.item_label_bold = item_label_bold
        db.session.commit()
        return CatalogService.serialize_home_category_display(setting)

    @staticmethod
    def category_descendant_ids(category_id):
        """Return a safe, cycle-resistant list containing a category and all descendants."""
        root_id = int(category_id)
        rows = Category.query.filter(Category.is_active.is_(True)).all()
        children = {}
        for row in rows:
            if row.parent_id is not None:
                children.setdefault(int(row.parent_id), []).append(int(row.id))

        result = []
        queue = [root_id]
        visited = set()
        while queue:
            current = queue.pop(0)
            if current in visited:
                continue
            visited.add(current)
            result.append(current)
            queue.extend(children.get(current, []))
        return result

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
    def product_side_category_references(category_ids):
        """Return side categories and their circles for the roots of selected catalog categories."""
        normalized_category_ids = []
        for raw in category_ids or []:
            try:
                category_id = int(raw)
            except (TypeError, ValueError):
                continue
            if category_id > 0 and category_id not in normalized_category_ids:
                normalized_category_ids.append(category_id)

        if not normalized_category_ids:
            return []

        active_categories = Category.query.filter(Category.is_active.is_(True)).all()
        parent_by_id = {int(row.id): row.parent_id for row in active_categories}
        selected_root_ids = set()

        for category_id in normalized_category_ids:
            current_id = category_id
            visited = set()
            while current_id and current_id not in visited:
                visited.add(current_id)
                parent_id = parent_by_id.get(int(current_id))
                if parent_id is None:
                    if int(current_id) in parent_by_id:
                        selected_root_ids.add(int(current_id))
                    break
                current_id = int(parent_id)

        if not selected_root_ids:
            return []

        rows = (
            SideCategory.query
            .filter(
                SideCategory.is_active.is_(True),
                SideCategory.root_category_id.in_(selected_root_ids),
            )
            .order_by(SideCategory.sort_order, SideCategory.name, SideCategory.id)
            .all()
        )
        return [
            CatalogService._serialize_side_category(row, include_circles=True)
            for row in rows
        ]

    @staticmethod
    def default_side_circle_display():
        return {
            "grid_columns": 3,
            "item_width": 88,
            "item_height": 88,
            "item_shape": "circle",
            "item_corner_radius": 18,
            "item_spacing": 8,
            "item_label_font_size": 10,
            "item_label_bold": True,
            "section_spacing": 14,
            "title_font_size": 15,
            "show_empty_state": True,
        }

    @staticmethod
    def serialize_side_circle_display(setting=None):
        values = CatalogService.default_side_circle_display()
        if setting is not None:
            values.update({
                "grid_columns": int(setting.grid_columns),
                "item_width": int(setting.item_width),
                "item_height": int(setting.item_height),
                "item_shape": setting.item_shape,
                "item_corner_radius": int(setting.item_corner_radius),
                "item_spacing": int(setting.item_spacing),
                "item_label_font_size": int(setting.item_label_font_size),
                "item_label_bold": bool(setting.item_label_bold),
                "section_spacing": int(setting.section_spacing),
                "title_font_size": int(setting.title_font_size),
                "show_empty_state": bool(setting.show_empty_state),
            })
        return values

    @staticmethod
    def get_side_circle_display():
        setting = SideCircleDisplaySetting.query.filter_by(scope_key="all").first()
        return CatalogService.serialize_side_circle_display(setting)

    @staticmethod
    def save_side_circle_display(payload):
        grid_columns = max(2, min(5, int(payload.get("grid_columns", 3))))
        item_width = max(48, min(180, int(payload.get("item_width", 88))))
        item_height = max(48, min(180, int(payload.get("item_height", 88))))
        item_shape = str(payload.get("item_shape", "circle")).strip().lower()
        if item_shape not in {"circle", "rounded", "square"}:
            raise ValueError("شكل الدوائر غير صالح.")
        item_corner_radius = max(0, min(90, int(payload.get("item_corner_radius", 18))))
        item_spacing = max(0, min(30, int(payload.get("item_spacing", 8))))
        item_label_font_size = max(7, min(24, int(payload.get("item_label_font_size", 10))))
        item_label_bold = bool(payload.get("item_label_bold", True))
        section_spacing = max(4, min(40, int(payload.get("section_spacing", 14))))
        title_font_size = max(10, min(28, int(payload.get("title_font_size", 15))))
        show_empty_state = bool(payload.get("show_empty_state", True))

        setting = SideCircleDisplaySetting.query.filter_by(scope_key="all").first()
        if setting is None:
            setting = SideCircleDisplaySetting(scope_key="all")
            db.session.add(setting)

        setting.grid_columns = grid_columns
        setting.item_width = item_width
        setting.item_height = item_height
        setting.item_shape = item_shape
        setting.item_corner_radius = item_corner_radius
        setting.item_spacing = item_spacing
        setting.item_label_font_size = item_label_font_size
        setting.item_label_bold = item_label_bold
        setting.section_spacing = section_spacing
        setting.title_font_size = title_font_size
        setting.show_empty_state = show_empty_state
        db.session.commit()
        return CatalogService.serialize_side_circle_display(setting)

    @staticmethod
    def _circle_root_category_id(circle):
        side = db.session.get(SideCategory, circle.side_category_id)
        return int(side.root_category_id) if side else None

    @staticmethod
    def _serialize_side_circle_group(group, include_circles=True):
        root = db.session.get(Category, group.root_category_id) if group.root_category_id else None
        circles = []
        if include_circles:
            assignments = (
                SideCircleDisplayGroupItem.query
                .filter_by(group_id=group.id)
                .order_by(SideCircleDisplayGroupItem.sort_order, SideCircleDisplayGroupItem.id)
                .all()
            )
            for assignment in assignments:
                circle = db.session.get(SideCategoryCircle, assignment.circle_id)
                if circle is None or not circle.is_active:
                    continue
                asset = db.session.get(MediaAsset, circle.image_asset_id) if circle.image_asset_id else None
                circles.append({
                    "id": circle.id,
                    "name": circle.name,
                    "slug": circle.slug,
                    "side_category_id": circle.side_category_id,
                    "sort_order": assignment.sort_order,
                    "image_url": asset.url if asset else None,
                })
        return {
            "id": group.id,
            "root_category_id": group.root_category_id,
            "root_category_name": root.name if root else None,
            "name": group.name,
            "slug": group.slug,
            "sort_order": int(group.sort_order),
            "show_view_all": bool(group.show_view_all),
            "is_active": bool(group.is_active),
            "circles": circles,
        }

    @staticmethod
    def list_side_circle_groups(root_category_id=None, include_archived=False, public_scope=False):
        query = SideCircleDisplayGroup.query
        if not include_archived:
            query = query.filter(SideCircleDisplayGroup.is_active.is_(True))
        if public_scope:
            if root_category_id is None:
                query = query.filter(SideCircleDisplayGroup.root_category_id.is_(None))
            else:
                query = query.filter(
                    or_(
                        SideCircleDisplayGroup.root_category_id.is_(None),
                        SideCircleDisplayGroup.root_category_id == int(root_category_id),
                    )
                )
        elif root_category_id is not None:
            query = query.filter(SideCircleDisplayGroup.root_category_id == int(root_category_id))
        rows = query.order_by(
            SideCircleDisplayGroup.sort_order,
            SideCircleDisplayGroup.name,
            SideCircleDisplayGroup.id,
        ).all()
        return [CatalogService._serialize_side_circle_group(row) for row in rows]

    @staticmethod
    def create_side_circle_group(payload):
        name = (payload.get("name") or "").strip()
        if not name:
            raise ValueError("اسم مجموعة الدوائر مطلوب.")
        root_id_raw = payload.get("root_category_id")
        root_id = None if root_id_raw in (None, "", 0, "0", "-1") else int(root_id_raw)
        if root_id is not None:
            CatalogService._require_top_level_category(root_id)

        slug = (payload.get("slug") or "").strip().lower() or _slugify(name, fallback="circle-group")
        base_slug = slug
        idx = 2
        while SideCircleDisplayGroup.query.filter_by(slug=slug).first():
            slug = f"{base_slug}-{idx}"[:180]
            idx += 1

        row = SideCircleDisplayGroup(
            root_category_id=root_id,
            name=name,
            slug=slug,
            sort_order=int(payload.get("sort_order", 0)),
            show_view_all=bool(payload.get("show_view_all", True)),
        )
        db.session.add(row)
        db.session.flush()
        CatalogService._set_side_circle_group_items(row, payload.get("circle_ids", []))
        db.session.commit()
        return CatalogService._serialize_side_circle_group(row)

    @staticmethod
    def _set_side_circle_group_items(group, circle_ids):
        normalized = []
        root_id = int(group.root_category_id) if group.root_category_id else None
        for raw in circle_ids or []:
            circle = db.session.get(SideCategoryCircle, int(raw))
            if circle is None or not circle.is_active:
                raise ValueError("إحدى الدوائر المحددة غير موجودة أو مؤرشفة.")
            if root_id is not None and CatalogService._circle_root_category_id(circle) != root_id:
                raise ValueError("كل دوائر المجموعة يجب أن تنتمي إلى القسم الرئيسي المحدد للمجموعة.")
            if circle.id not in normalized:
                normalized.append(circle.id)

        SideCircleDisplayGroupItem.query.filter_by(group_id=group.id).delete()
        for position, circle_id in enumerate(normalized):
            db.session.add(
                SideCircleDisplayGroupItem(
                    group_id=group.id,
                    circle_id=circle_id,
                    sort_order=position,
                )
            )

    @staticmethod
    def update_side_circle_group(group_id, payload):
        row = db.session.get(SideCircleDisplayGroup, group_id)
        if row is None:
            raise LookupError("circle display group not found")

        if "root_category_id" in payload:
            root_id_raw = payload.get("root_category_id")
            root_id = None if root_id_raw in (None, "", 0, "0", "-1") else int(root_id_raw)
            if root_id is not None:
                CatalogService._require_top_level_category(root_id)
            row.root_category_id = root_id

        if "name" in payload:
            name = (payload.get("name") or "").strip()
            if not name:
                raise ValueError("اسم مجموعة الدوائر مطلوب.")
            row.name = name
        if "slug" in payload and (payload.get("slug") or "").strip():
            row.slug = _slugify(payload["slug"], fallback=f"circle-group-{row.id}")
        if "sort_order" in payload:
            row.sort_order = int(payload["sort_order"])
        if "show_view_all" in payload:
            row.show_view_all = bool(payload.get("show_view_all"))

        if "circle_ids" in payload:
            CatalogService._set_side_circle_group_items(row, payload.get("circle_ids", []))

        duplicate = (
            SideCircleDisplayGroup.query
            .filter(
                SideCircleDisplayGroup.id != row.id,
                SideCircleDisplayGroup.slug == row.slug,
            )
            .first()
        )
        if duplicate:
            db.session.rollback()
            raise ValueError("Slug مجموعة الدوائر مستخدم مسبقًا.")

        db.session.commit()
        return CatalogService._serialize_side_circle_group(row)

    @staticmethod
    def archive_side_circle_group(group_id):
        row = db.session.get(SideCircleDisplayGroup, group_id)
        if row is None:
            raise LookupError("circle display group not found")
        row.is_active = False
        db.session.commit()

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
    def _swap_sort_order(model, current_id, direction, scope_filters):
        current = db.session.get(model, int(current_id))
        if current is None or not current.is_active:
            raise LookupError("item not found")
        if direction not in {"up", "down"}:
            raise ValueError("invalid reorder direction")

        query = model.query.filter(*scope_filters, model.is_active.is_(True))
        rows = query.order_by(model.sort_order, model.id).all()
        index = next((i for i, row in enumerate(rows) if row.id == current.id), None)
        if index is None:
            raise LookupError("item not found")
        neighbor_index = index - 1 if direction == "up" else index + 1
        if neighbor_index < 0 or neighbor_index >= len(rows):
            return CatalogService._serialize_side_category(current) if model is SideCategory else CatalogService._serialize_side_category_circle(current, include_products=True)

        neighbor = rows[neighbor_index]
        current_order, neighbor_order = current.sort_order, neighbor.sort_order
        if current_order == neighbor_order:
            current.sort_order = neighbor_index
            neighbor.sort_order = index
        else:
            current.sort_order = neighbor_order
            neighbor.sort_order = current_order
        db.session.commit()

        return (
            CatalogService._serialize_side_category(current)
            if model is SideCategory
            else CatalogService._serialize_side_category_circle(current, include_products=True)
        )

    @staticmethod
    def reorder_side_category(side_category_id, direction):
        current = db.session.get(SideCategory, int(side_category_id))
        if current is None:
            raise LookupError("side category not found")
        return CatalogService._swap_sort_order(
            SideCategory,
            side_category_id,
            direction,
            [SideCategory.root_category_id == current.root_category_id],
        )

    @staticmethod
    def reorder_side_category_circle(circle_id, direction):
        current = db.session.get(SideCategoryCircle, int(circle_id))
        if current is None:
            raise LookupError("side category circle not found")
        return CatalogService._swap_sort_order(
            SideCategoryCircle,
            circle_id,
            direction,
            [SideCategoryCircle.side_category_id == current.side_category_id],
        )

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
    def _product_category_belongs_to_root(product_category_id, root_category_id):
        current_id = product_category_id
        visited = set()
        while current_id is not None and current_id not in visited:
            visited.add(current_id)
            category = db.session.get(Category, int(current_id))
            if category is None:
                return False
            if category.id == int(root_category_id):
                return True
            current_id = category.parent_id
        return False

    @staticmethod
    def set_product_side_category_circles(product_id, circle_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")
        normalized = []
        product_category_ids = [
            int(row.category_id)
            for row in ProductCategory.query.filter_by(product_id=product_id).all()
        ]
        for raw in circle_ids or []:
            circle_id = int(raw)
            circle = db.session.get(SideCategoryCircle, circle_id)
            if circle is None or not circle.is_active:
                raise ValueError("إحدى دوائر الفئات الجانبية غير موجودة أو مؤرشفة.")
            side_category = db.session.get(SideCategory, circle.side_category_id)
            if side_category is None or not side_category.is_active:
                raise ValueError("الفئة الجانبية المرتبطة بهذه الدائرة غير متاحة.")
            if not any(
                CatalogService._product_category_belongs_to_root(category_id, side_category.root_category_id)
                for category_id in product_category_ids
            ):
                raise ValueError(
                    "المنتج يجب أن يكون مرتبطًا بالقسم الرئيسي الخاص بالفئة الجانبية "
                    "أو بأحد فروعه قبل ربطه بهذه الدائرة."
                )
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
                if category.parent_id is None:
                    from ...models import SideCategory
                    linked_side_category = SideCategory.query.filter_by(
                        root_category_id=category.id,
                        is_active=True,
                    ).first()
                    if linked_side_category:
                        raise ValueError("لا يمكن تحويل قسم رئيسي مستخدم في الفئات الجانبية إلى فئة فرعية.")
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
        if category.parent_id is None:
            side_categories = SideCategory.query.filter_by(
                root_category_id=category_id,
                is_active=True,
            ).all()
            for side_category in side_categories:
                side_category.is_active = False
                SideCategoryCircle.query.filter_by(
                    side_category_id=side_category.id,
                    is_active=True,
                ).update({"is_active": False})
        db.session.commit()

    @staticmethod
    def _serialize_product(product):
        brand = db.session.get(Brand, product.brand_id) if product.brand_id else None
        return {
            "id": product.id,
            "sku": product.sku,
            "name": product.name,
            "slug": product.slug,
            "description": product.description,
            "short_description": product.description,
            "base_price_sar": str(product.base_price),
            "compare_at_price": str(product.compare_at_price) if product.compare_at_price is not None else None,
            "base_currency_id": product.base_currency_id,
            "status": product.status,
            "material": product.material,
            "care_instructions": product.care_instructions,
            "brand_id": product.brand_id,
            "brand": {"id": brand.id, "name": brand.name} if brand else None,
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
            product_type=(payload.get("product_type") or "").strip() or None,
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
    def get_product(product_id, customer_id=None, currency_id=None):
        product = db.session.get(Product, product_id)
        if not product:
            raise LookupError("product not found")
        snapshot = CatalogService.wizard_snapshot(product_id)
        snapshot["product_card_global_settings"] = CatalogService.product_card_display_settings()
        snapshot["product_card_settings"] = CatalogService.product_card_display_settings(product_id)
        display_row = db.session.get(ProductDisplaySettings, product_id)
        snapshot["product_card_overrides"] = dict((display_row.card_overrides_json or {}) if display_row else {})
        brand = db.session.get(Brand, product.brand_id) if product.brand_id else None
        snapshot["product"]["brand"] = {
            "id": brand.id,
            "name": brand.name,
        } if brand else None
        # Use exactly the same centralized customer/city/area/currency pricing
        # path as the storefront feed. This keeps the product detail price identical
        # to the price already shown on the home product card.
        from ...models import Customer
        customer = db.session.get(Customer, int(customer_id)) if customer_id else None
        try:
            ctx, price = price_for_customer(
                base_price_sar=Decimal(product.base_price),
                customer_id=customer.id if customer else None,
                city_id=customer.city_id if customer else None,
                area_id=customer.city_area_id if customer else None,
                currency_id=int(currency_id) if currency_id else None,
            )
            currency = db.session.get(Currency, ctx.currency_id)
            snapshot["product"]["display_price"] = str(price.final)
            if product.compare_at_price is not None:
                compare_priced = calculate_customer_price(
                    Decimal(product.compare_at_price),
                    price.fx_rate,
                    ctx.rule,
                    override_percent=ctx.override_percent,
                    override_fixed=ctx.override_fixed,
                    location_percent=ctx.location_percent,
                    location_fixed_sar=ctx.location_fixed_sar,
                )
                snapshot["product"]["display_compare_price"] = str(compare_priced.final)
                snapshot["product"]["base_compare_at_price_sar"] = str(product.compare_at_price)
            else:
                snapshot["product"]["display_compare_price"] = None
            snapshot["product"]["display_currency"] = {
                "id": ctx.currency_id, "code": ctx.currency_code,
                "symbol": currency.symbol if currency else ctx.currency_code,
            }
        except (LookupError, ValueError, InvalidOperation):
            # Preserve the legacy payload only when pricing configuration itself
            # is incomplete; never reimplement pricing here.
            pass
        snapshot["product"]["short_description"] = product.description or ""
        return snapshot

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
    @staticmethod
    def set_product_size_guides(product_id, guide_ids):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")

        normalized_ids = []
        for raw in guide_ids or []:
            try:
                guide_id = int(raw.get("id") if isinstance(raw, dict) else raw)
            except (TypeError, ValueError):
                raise ValueError("معرف جدول المقاسات غير صحيح.")
            if guide_id <= 0:
                raise ValueError("معرف جدول المقاسات غير صحيح.")
            guide = db.session.get(SizeGuide, guide_id)
            if guide is None:
                raise ValueError(f"size guide {guide_id} not found")
            if not guide.is_active:
                raise ValueError("لا يمكن اختيار جدول مقاسات مؤرشف.")
            if guide_id not in normalized_ids:
                normalized_ids.append(guide_id)

        ProductSizeGuideReference.query.filter_by(product_id=product_id).delete()
        for position, guide_id in enumerate(normalized_ids):
            db.session.add(
                ProductSizeGuideReference(
                    product_id=product_id,
                    guide_id=guide_id,
                    sort_order=position,
                )
            )

        db.session.commit()
        return {"guide_ids": normalized_ids}


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
    def set_product_badges(product_id, badges):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")

        # Backward compatible input:
        # [1, 2] or [{"badge_id": 1, ...visual overrides...}, ...]
        items = []
        for raw in badges or []:
            if isinstance(raw, dict):
                raw_settings = raw.get("settings")
                if not isinstance(raw_settings, dict):
                    raw_settings = {}
                allowed_settings = {
                    "visible", "position", "font_size", "font_weight",
                    "background_color", "background_opacity", "text_color",
                    "border_radius", "padding_horizontal", "padding_vertical",
                    "text_decoration", "border_width", "border_color",
                }
                settings = {
                    str(key): raw_settings[key]
                    for key in allowed_settings
                    if key in raw_settings
                }
                # Accept the ergonomic flat form used by the admin editor too.
                aliases = {
                    "position": "position",
                    "font_size": "font_size",
                    "font_weight": "font_weight",
                    "background_color": "background_color",
                    "background_opacity": "background_opacity",
                    "text_color": "text_color",
                    "border_radius": "border_radius",
                    "padding_horizontal": "padding_horizontal",
                    "padding_vertical": "padding_vertical",
                    "text_decoration": "text_decoration",
                    "border_width": "border_width",
                    "border_color": "border_color",
                    "visible": "visible",
                }
                for source, target in aliases.items():
                    if source in raw:
                        settings[target] = raw[source]
                items.append({
                    "badge_id": int(raw.get("badge_id") or raw.get("id")),
                    "duration_days": int(raw.get("duration_days") or 0),
                    "custom_text": str(raw.get("custom_text") or "").strip() or None,
                    "sort_order": raw.get("sort_order"),
                    "settings": settings,
                })
            else:
                items.append({
                    "badge_id": int(raw),
                    "duration_days": 0,
                    "custom_text": None,
                    "sort_order": None,
                    "settings": {},
                })

        normalized = []
        seen = set()
        for index, item in enumerate(items):
            badge_id = int(item["badge_id"])
            badge = db.session.get(Badge, badge_id)
            if badge is None:
                raise ValueError(f"badge {badge_id} not found")
            if badge_id in seen:
                continue
            seen.add(badge_id)
            duration_days = max(0, min(int(item.get("duration_days") or 0), 3650))
            starts_at = datetime.now(timezone.utc)
            ends_at = starts_at + timedelta(days=duration_days) if duration_days else None
            settings = dict(item.get("settings") or {})
            if "visible" in settings:
                settings["visible"] = bool(settings["visible"])
            if "font_size" in settings:
                settings["font_size"] = max(6.0, min(float(settings["font_size"]), 32.0))
            if "font_weight" in settings:
                settings["font_weight"] = max(300, min(int(settings["font_weight"]), 900))
            if "background_opacity" in settings:
                settings["background_opacity"] = max(0.0, min(float(settings["background_opacity"]), 1.0))
            if "border_radius" in settings:
                settings["border_radius"] = max(0.0, min(float(settings["border_radius"]), 30.0))
            for dim in ("padding_horizontal", "padding_vertical", "border_width"):
                if dim in settings:
                    settings[dim] = max(0.0, min(float(settings[dim]), 30.0))
            if settings.get("text_decoration") not in (None, "", "none", "line_through"):
                raise ValueError("نوع خط الشارة غير صالح.")
            if settings.get("position") not in (None, "", "top_left", "top_right", "bottom_left", "bottom_right",
                                                "above_image",
                                                "before_name", "before_name_same_row", "before_name_new_row",
                                                "after_name", "after_name_same_row", "after_name_new_row",
                                                "before_description", "before_description_same_row", "before_description_new_row",
                                                "after_description", "after_description_same_row", "after_description_new_row",
                                                "below_description",
                                                "before_price", "before_price_same_row", "before_price_new_row",
                                                "after_price_same_row", "after_price_new_row", "after_price", "below_price",
                                                "right_of_image",
                                                "before_details", "after_details", "after_details_same_row", "after_details_new_row", "last"):
                raise ValueError("موقع الشارة غير صالح.")
            for color_key in ("background_color", "text_color", "border_color"):
                if color_key in settings:
                    import re
                    if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(settings[color_key]).strip()):
                        raise ValueError(f"لون الشارة {color_key} غير صالح.")
                    settings[color_key] = str(settings[color_key]).strip().lower()
            raw_order = item.get("sort_order")
            try:
                sort_order = int(raw_order)
            except (TypeError, ValueError):
                sort_order = index
            normalized.append({
                "badge_id": badge_id,
                "duration_days": duration_days,
                "custom_text": item.get("custom_text"),
                "starts_at": starts_at,
                "ends_at": ends_at,
                "sort_order": sort_order,
                "settings": settings,
            })

        normalized.sort(key=lambda x: x["sort_order"])
        ProductBadge.query.filter_by(product_id=product_id).delete()
        for position, item in enumerate(normalized):
            db.session.add(ProductBadge(
                product_id=product_id,
                badge_id=item["badge_id"],
                starts_at=item["starts_at"],
                ends_at=item["ends_at"],
                custom_text=item["custom_text"],
                position=str(position),
                sort_order=position,
                settings_json=item["settings"],
            ))
        db.session.commit()
        return [
            {
                "badge_id": item["badge_id"],
                "duration_days": item["duration_days"],
                "custom_text": item["custom_text"],
                "sort_order": index,
                "settings": item["settings"],
                "starts_at": item["starts_at"].isoformat(),
                "ends_at": item["ends_at"].isoformat() if item["ends_at"] else None,
            }
            for index, item in enumerate(normalized)
        ]

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
        media = (
            ProductMedia.query
            .filter(
                ProductMedia.id == int(media_id),
                ProductMedia.product_id == int(product_id),
            )
            .first()
        )
        if media is None:
            raise LookupError("product media not found")

        # Remove only the product-media relation. Keep the MediaAsset itself
        # because it may be shared by another storefront entity or historical data.
        deleted = (
            ProductMedia.query
            .filter(
                ProductMedia.id == media.id,
                ProductMedia.product_id == int(product_id),
            )
            .delete(synchronize_session=False)
        )
        if deleted != 1:
            db.session.rollback()
            raise LookupError("product media not found")

        db.session.commit()
        return {"id": int(media_id), "product_id": int(product_id)}

    @staticmethod
    def _variant_sku_token(value):
        value = (value or "").strip().upper()
        value = re.sub(r"[^A-Z0-9]+", "-", value).strip("-")
        return value[:24]

    @staticmethod
    def _variant_combination_exists(product_id, color_id, size_id, exclude_variant_id=None):
        query = ProductVariant.query.filter(
            ProductVariant.product_id == product_id,
            ProductVariant.color_id.is_(color_id) if color_id is None else ProductVariant.color_id == color_id,
            ProductVariant.size_id.is_(size_id) if size_id is None else ProductVariant.size_id == size_id,
        )
        if exclude_variant_id is not None:
            query = query.filter(ProductVariant.id != exclude_variant_id)
        return query.first() is not None

    @staticmethod
    def _generate_variant_sku(product_id, color_id=None, size_id=None, exclude_variant_id=None):
        product = db.session.get(Product, product_id)
        if product is None:
            raise LookupError("product not found")

        parts = [CatalogService._variant_sku_token(product.sku)]
        if color_id is not None:
            color = db.session.get(Color, int(color_id))
            if color is None:
                raise ValueError("color not found")
            color_token = CatalogService._variant_sku_token(color.name) or f"C{color.id}"
            parts.append(color_token)
        if size_id is not None:
            size = db.session.get(Size, int(size_id))
            if size is None:
                raise ValueError("size not found")
            parts.append(CatalogService._variant_sku_token(size.code or size.label))

        base = "-".join(x for x in parts if x)[:112].rstrip("-")
        if not base:
            base = f"PRODUCT-{product_id}"
        if color_id is None and size_id is None:
            base = f"{base}-V"

        candidate = base
        suffix = 2
        while ProductVariant.query.filter(
            ProductVariant.sku == candidate,
            ProductVariant.id != (exclude_variant_id or 0),
        ).first() is not None:
            suffix_text = f"-{suffix}"
            candidate = f"{base[:120-len(suffix_text)]}{suffix_text}"
            suffix += 1
        return candidate

    @staticmethod
    def _validate_variant_combination(product_id, color_id, size_id, exclude_variant_id=None):
        if CatalogService._variant_combination_exists(
            product_id, color_id, size_id, exclude_variant_id=exclude_variant_id
        ):
            raise ValueError("تركيبة اللون والمقاس لهذا المنتج موجودة بالفعل.")

    @staticmethod
    def update_variant(product_id, variant_id, payload):
        variant = db.session.get(ProductVariant, variant_id)
        if variant is None or variant.product_id != product_id:
            raise LookupError("variant not found")
        requested_sku = (payload.get("sku") or "").strip().upper()
        color_id = int(payload["color_id"]) if payload.get("color_id") not in (None, "") else None
        size_id = int(payload["size_id"]) if payload.get("size_id") not in (None, "") else None
        color_ref = ProductColorReference.query.filter_by(product_id=product_id, color_id=color_id).first() if color_id else None
        size_ref = ProductSizeReference.query.filter_by(product_id=product_id, size_id=size_id).first() if size_id else None
        if color_id and color_ref is None and color_id != variant.color_id:
            raise ValueError("اختر اللون أولًا ضمن ألوان المنتج.")
        if size_id and size_ref is None and size_id != variant.size_id:
            raise ValueError("اختر المقاس أولًا ضمن مقاسات المنتج.")
        CatalogService._validate_variant_combination(
            product_id,
            color_id,
            size_id,
            exclude_variant_id=variant_id,
        )
        sku = requested_sku or CatalogService._generate_variant_sku(
            product_id,
            color_id,
            size_id,
            exclude_variant_id=variant_id,
        )
        duplicate = ProductVariant.query.filter(
            ProductVariant.id != variant_id,
            ProductVariant.sku == sku,
        ).first()
        if duplicate:
            raise ValueError("variant sku already exists")
        variant.sku = sku
        variant.color_id = color_id
        variant.size_id = size_id
        variant.barcode = (payload.get("barcode") or "").strip() or None
        variant.weight = Decimal(str(payload["weight"])) if payload.get("weight") not in (None, "") else None
        variant.status = (payload.get("status") or variant.status).strip()
        db.session.commit()
        return {"id": variant.id, "sku": variant.sku, "color_id": variant.color_id, "size_id": variant.size_id, "barcode": variant.barcode, "status": variant.status}

    @staticmethod
    def copy_variant(product_id, source_variant_id, color_id):
        source = db.session.get(ProductVariant, int(source_variant_id))
        if source is None or source.product_id != product_id:
            raise LookupError("source variant not found")
        if not source.is_active:
            raise ValueError("لا يمكن نسخ متغير مؤرشف.")

        target_color_id = int(color_id) if color_id not in (None, "") else None
        if target_color_id is None:
            raise ValueError("اختر لونًا لإكمال نسخ المتغير.")

        if ProductColorReference.query.filter_by(
            product_id=product_id,
            color_id=target_color_id,
        ).first() is None:
            raise ValueError("اللون المختار غير مرتبط بهذا المنتج.")

        CatalogService._validate_variant_combination(
            product_id,
            target_color_id,
            source.size_id,
        )

        variant = ProductVariant(
            product_id=product_id,
            sku=CatalogService._generate_variant_sku(
                product_id,
                target_color_id,
                source.size_id,
            ),
            color_id=target_color_id,
            size_id=source.size_id,
            barcode=None,
            weight=source.weight,
            status="active",
        )
        db.session.add(variant)
        db.session.flush()

        source_stock_rows = StockInventory.query.filter_by(
            variant_id=source.id
        ).all()
        for row in source_stock_rows:
            db.session.add(
                StockInventory(
                    location_id=row.location_id,
                    variant_id=variant.id,
                    on_hand=int(row.on_hand or 0),
                    reserved=int(row.reserved or 0),
                    available=int(row.available or 0),
                    reorder_level=int(row.reorder_level or 0),
                )
            )

        db.session.commit()
        return {
            "variant": {
                "id": variant.id,
                "sku": variant.sku,
                "color_id": variant.color_id,
                "size_id": variant.size_id,
                "barcode": variant.barcode,
                "weight": str(variant.weight) if variant.weight is not None else None,
            },
            "copied_stock_count": len(source_stock_rows),
        }

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
        requested_sku = (payload.get("sku") or "").strip().upper()
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
        CatalogService._validate_variant_combination(product_id, color_id, size_id)
        sku = requested_sku or CatalogService._generate_variant_sku(product_id, color_id, size_id)
        if ProductVariant.query.filter_by(sku=sku).first():
            raise ValueError("variant sku already exists")
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
    def generate_variants(product_id, color_ids=None, size_ids=None):
        if db.session.get(Product, product_id) is None:
            raise LookupError("product not found")

        colors = []
        for raw in color_ids or []:
            color_id = int(raw)
            if color_id not in colors:
                colors.append(color_id)
        sizes = []
        for raw in size_ids or []:
            size_id = int(raw)
            if size_id not in sizes:
                sizes.append(size_id)

        selected_colors = [
            cid for cid in colors
            if ProductColorReference.query.filter_by(product_id=product_id, color_id=cid).first()
        ]
        selected_sizes = [
            sid for sid in sizes
            if ProductSizeReference.query.filter_by(product_id=product_id, size_id=sid).first()
        ]
        if colors and len(selected_colors) != len(colors):
            raise ValueError("بعض الألوان ليست مرتبطة بالمنتج.")
        if sizes and len(selected_sizes) != len(sizes):
            raise ValueError("بعض المقاسات ليست مرتبطة بالمنتج.")

        color_values = selected_colors or [None]
        size_values = selected_sizes or [None]
        created = []
        skipped = 0

        for color_id in color_values:
            for size_id in size_values:
                if CatalogService._variant_combination_exists(product_id, color_id, size_id):
                    skipped += 1
                    continue
                variant = ProductVariant(
                    product_id=product_id,
                    sku=CatalogService._generate_variant_sku(product_id, color_id, size_id),
                    color_id=color_id,
                    size_id=size_id,
                    status="active",
                )
                db.session.add(variant)
                db.session.flush()
                created.append({
                    "id": variant.id,
                    "sku": variant.sku,
                    "color_id": variant.color_id,
                    "size_id": variant.size_id,
                })

        db.session.commit()
        return {
            "created": created,
            "created_count": len(created),
            "skipped_count": skipped,
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
    def category_filters(category_id, include_descendants=False):
        root_id = int(category_id)
        scope_ids = (
            CatalogService.category_descendant_ids(root_id)
            if include_descendants
            else [root_id]
        )
        rows = (
            CategoryFilterDefinition.query
            .filter(
                CategoryFilterDefinition.category_id.in_(scope_ids),
                CategoryFilterDefinition.is_active.is_(True),
            )
            .order_by(CategoryFilterDefinition.sort_order, CategoryFilterDefinition.id)
            .all()
        )

        merged = {}
        for row in rows:
            key = (
                (row.name or "").strip().casefold(),
                (row.filter_type or "").strip().casefold(),
            )
            item = merged.get(key)
            if item is None:
                item = {
                    "id": row.id,
                    "name": row.name,
                    "filter_type": row.filter_type,
                    "values": [],
                }
                merged[key] = item

            existing_value_ids = {int(value["id"]) for value in item["values"]}
            values = (
                CategoryFilterValue.query
                .filter_by(filter_id=row.id, is_active=True)
                .order_by(CategoryFilterValue.sort_order, CategoryFilterValue.id)
                .all()
            )
            for value in values:
                if int(value.id) in existing_value_ids:
                    continue
                item["values"].append({
                    "id": value.id,
                    "label": value.label,
                    "slug": value.slug,
                    "sort_order": value.sort_order,
                })
                existing_value_ids.add(int(value.id))

        return list(merged.values())

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

        if "card_overrides" in payload:
            raw = payload.get("card_overrides")
            if raw in (None, {}):
                settings.card_overrides_json = {}
            elif not isinstance(raw, dict):
                raise ValueError("card_overrides must be an object")
            else:
                global_settings = CatalogService.product_card_display_settings()
                allowed = set(global_settings.keys())
                clean = {}
                color_re = re.compile(r"^#[0-9a-fA-F]{6}$")
                for key, value in raw.items():
                    if key not in allowed:
                        continue
                    global_value = global_settings.get(key)
                    if isinstance(global_value, bool):
                        clean[key] = bool(value)
                    elif isinstance(global_value, (int, float)) and not isinstance(global_value, bool):
                        try:
                            clean[key] = float(value)
                        except (TypeError, ValueError):
                            raise ValueError(f"قيمة تخصيص بطاقة المنتج غير صالحة: {key}")
                    elif isinstance(value, str) and (
                        str(global_value or "").startswith("#") or key.endswith("_color")
                    ):
                        if not color_re.fullmatch(value.strip()):
                            raise ValueError(f"لون تخصيص بطاقة المنتج غير صالح: {key}")
                        clean[key] = value.strip().lower()
                    else:
                        clean[key] = str(value).strip()
                settings.card_overrides_json = clean

        if "delivery_badges" in payload:
            raw_badges = payload.get("delivery_badges")
            if raw_badges is None:
                raw_badges = []
            if not isinstance(raw_badges, list):
                raise ValueError("delivery_badges must be a list")
            color_re = re.compile(r"^#[0-9a-fA-F]{6}$")
            normalized = []
            for raw_badge in raw_badges:
                if not isinstance(raw_badge, dict):
                    continue
                text = str(raw_badge.get("text") or "").strip()[:120]
                if not text:
                    continue
                bg = str(raw_badge.get("background_color") or "#f5f5f5").strip()
                fg = str(raw_badge.get("text_color") or "#111111").strip()
                if not color_re.fullmatch(bg) or not color_re.fullmatch(fg):
                    raise ValueError("ألوان شارة التوصيل يجب أن تكون بصيغة HEX.")
                try:
                    font_size = max(7.0, min(24.0, float(raw_badge.get("font_size", 9))))
                except (TypeError, ValueError):
                    font_size = 9.0
                normalized.append({
                    "id": str(raw_badge.get("id") or uuid4().hex[:10]),
                    "text": text,
                    "icon": str(raw_badge.get("icon") or "local_shipping").strip()[:40],
                    "section": str(raw_badge.get("section") or "shipping").strip()[:40],
                    "background_color": bg.lower(),
                    "text_color": fg.lower(),
                    "font_size": font_size,
                    "visible": bool(raw_badge.get("visible", True)),
                    "sort_order": len(normalized),
                })
            settings.delivery_badges_json = normalized

        if "recommendation_settings" in payload:
            recommendation = payload.get("recommendation_settings")
            if recommendation is None:
                recommendation = {}
            if not isinstance(recommendation, dict):
                raise ValueError("recommendation_settings must be an object")
            source = str(recommendation.get("source") or "same_category").strip()
            allowed_sources = {"same_category", "parent_category", "root_category", "random_all"}
            if source not in allowed_sources:
                raise ValueError("مصدر التوصيات غير صالح.")
            try:
                limit = max(2, min(20, int(recommendation.get("limit", 10))))
            except (TypeError, ValueError):
                limit = 10
            settings.recommendation_settings_json = {
                "source": source,
                "limit": limit,
                "randomize": True,
            }

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
            "card_overrides": dict(settings.card_overrides_json or {}),
            "delivery_badges": list(settings.delivery_badges_json or []),
            "recommendation_settings": dict(settings.recommendation_settings_json or {}),
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
        current_size_guide_ids = {int(x.guide_id) for x in ProductSizeGuideReference.query.filter_by(product_id=product_id).all()} if product_id else set()

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

        # Build a flat, deterministic list for the admin product wizard.
        # The backend remains the authority for root-category compatibility.
        category_rows = Category.query.filter(Category.is_active.is_(True)).all()
        category_parent = {int(row.id): row.parent_id for row in category_rows}
        selected_root_ids = set()
        for category_id in current_category_ids:
            current = int(category_id)
            visited = set()
            while current and current not in visited:
                visited.add(current)
                parent_id = category_parent.get(current)
                if parent_id is None:
                    if current in category_parent:
                        selected_root_ids.add(current)
                    break
                current = int(parent_id)

        side_circle_rows = (
            db.session.query(SideCategoryCircle, SideCategory)
            .join(SideCategory, SideCategory.id == SideCategoryCircle.side_category_id)
            .filter(
                SideCategoryCircle.is_active.is_(True),
                SideCategory.is_active.is_(True),
            )
            .order_by(
                SideCategory.root_category_id,
                SideCategory.sort_order,
                SideCategory.name,
                SideCategoryCircle.sort_order,
                SideCategoryCircle.name,
                SideCategoryCircle.id,
            )
            .all()
        )

        available_side_category_circles = []
        for circle, side_category in side_circle_rows:
            root_id = int(side_category.root_category_id)
            root = db.session.get(Category, root_id)
            image = db.session.get(MediaAsset, circle.image_asset_id) if circle.image_asset_id else None
            available_side_category_circles.append({
                "id": circle.id,
                "side_category_id": side_category.id,
                "side_category_name": side_category.name,
                "root_category_id": root_id,
                "root_category_name": root.name if root else "—",
                "name": circle.name,
                "slug": circle.slug,
                "image_asset_id": circle.image_asset_id,
                "image_url": image.url if image else None,
                "badge_id": circle.badge_id,
                "sort_order": circle.sort_order,
                "product_count": (
                    db.session.query(ProductSideCategoryCircle.id)
                    .join(Product, Product.id == ProductSideCategoryCircle.product_id)
                    .filter(
                        ProductSideCategoryCircle.circle_id == circle.id,
                        Product.is_active.is_(True),
                        Product.status == "published",
                    )
                    .count()
                ),
                "compatible": (
                    not selected_root_ids
                    or root_id in selected_root_ids
                    or circle.id in current_side_circle_ids
                ),
                "selected": circle.id in current_side_circle_ids,
            })

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

        size_guide_reference_rows = (
            db.session.query(ProductSizeGuideReference, SizeGuide)
            .join(SizeGuide, SizeGuide.id == ProductSizeGuideReference.guide_id)
            .filter(
                ProductSizeGuideReference.product_id == product_id,
                SizeGuide.is_active.is_(True),
            )
            .order_by(ProductSizeGuideReference.sort_order, SizeGuide.id)
            .all()
        )
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
                    "style": row.style, "priority": row.priority,
                    "storefront_tab": row.storefront_tab,
                    "is_active": bool(row.is_active),
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
            "available_side_category_circles": available_side_category_circles,
            "selected_side_category_circle_ids": sorted(current_side_circle_ids),
            "policies": policies,
            "size_guides": [
                {
                    "id": row.id,
                    "name": row.name,
                    "guide_type": row.guide_type,
                    "fit_type": row.fit_type,
                    "intro_text": row.intro_text,
                    "product_columns": row.product_columns_json or [],
                    "body_columns": row.body_columns_json or [],
                    "selected": row.id in current_size_guide_ids,
                    "sort_order": next(
                        (
                            int(ref.sort_order)
                            for ref, guide in size_guide_reference_rows
                            if int(guide.id) == int(row.id)
                        ),
                        999999,
                    ),
                }
                for row in size_guides
            ],
        }

    @staticmethod
    def publish_product(product_id, notify_customers=True):
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

        if notify_customers:
            from ...services.notifications import NotificationService
            NotificationService.broadcast(
                "منتج جديد في التخفيض الصح",
                "تمت إضافة «" + product.name + "» إلى المتجر. اضغط لعرض تفاصيل المنتج.",
                {
                    "type": "new_product",
                    "screen_type": "product_details",
                    "product_id": product.id,
                    "target": "product",
                },
            )

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
        category_parent = {
            int(row.id): (int(row.parent_id) if row.parent_id is not None else None)
            for row in Category.query.all()
        }
        root_category_ids = set()
        for category in categories:
            current = int(category["id"])
            seen = set()
            while current not in seen:
                seen.add(current)
                parent = category_parent.get(current)
                if parent is None:
                    root_category_ids.add(current)
                    break
                current = int(parent)

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
        variant_rows = ProductVariant.query.filter_by(
            product_id=product_id,
        ).order_by(ProductVariant.id).all()
        stock_available_by_variant = {}
        stock_on_hand_by_variant = {}
        stock_reserved_by_variant = {}
        if variant_rows:
            stock_rows = (
                db.session.query(
                    StockInventory.variant_id,
                    StockInventory.on_hand,
                    StockInventory.reserved,
                    StockInventory.available,
                )
                .join(
                    InventoryLocation,
                    InventoryLocation.id == StockInventory.location_id,
                )
                .filter(
                    StockInventory.variant_id.in_([row.id for row in variant_rows]),
                    InventoryLocation.is_active.is_(True),
                )
                .all()
            )
            for stock_row in stock_rows:
                variant_key = int(stock_row.variant_id)
                stock_available_by_variant[variant_key] = (
                    stock_available_by_variant.get(variant_key, 0)
                    + max(0, int(stock_row.available or 0))
                )
                stock_on_hand_by_variant[variant_key] = (
                    stock_on_hand_by_variant.get(variant_key, 0)
                    + max(0, int(stock_row.on_hand or 0))
                )
                stock_reserved_by_variant[variant_key] = (
                    stock_reserved_by_variant.get(variant_key, 0)
                    + max(0, int(stock_row.reserved or 0))
                )

        variants = [
            {
                "id": variant.id,
                "sku": variant.sku,
                "color_id": variant.color_id,
                "size_id": variant.size_id,
                "barcode": variant.barcode,
                "weight": str(variant.weight) if variant.weight is not None else None,
                "status": variant.status,
                "available_qty": int(stock_available_by_variant.get(variant.id, 0)),
                "on_hand_qty": int(stock_on_hand_by_variant.get(variant.id, 0)),
                "reserved_qty": int(stock_reserved_by_variant.get(variant.id, 0)),
                "in_stock": bool(stock_available_by_variant.get(variant.id, 0) > 0),
            }
            for variant in variant_rows
        ]
        badge_rows = (
            db.session.query(ProductBadge, Badge)
            .join(Badge, Badge.id == ProductBadge.badge_id)
            .filter(ProductBadge.product_id == product_id)
            .order_by(ProductBadge.sort_order, ProductBadge.id)
            .all()
        )
        badges = [
            {
                "id": badge.id,
                "code": badge.code,
                "name": badge.name,
                "bg_color": badge.bg_color,
                "text_color": badge.text_color,
                "style": badge.style,
                "storefront_tab": badge.storefront_tab,
                "starts_at": row.starts_at.isoformat() if row.starts_at else None,
                "ends_at": row.ends_at.isoformat() if row.ends_at else None,
                "custom_text": row.custom_text,
                "position": row.position,
                "sort_order": int(row.sort_order or 0),
                "settings": dict(row.settings_json or {}),
            }
            for row, badge in badge_rows
        ]
        hashtag_rows = (
            db.session.query(ProductHashtag, Hashtag)
            .join(Hashtag, Hashtag.id == ProductHashtag.hashtag_id)
            .filter(ProductHashtag.product_id == product_id)
            .order_by(ProductHashtag.id)
            .all()
        )
        hashtags = [
            {
                "id": tag.id,
                "name": tag.name,
                "display_name": tag.display_name or ("#" + tag.name),
                "slug": tag.slug,
            }
            for row, tag in hashtag_rows
        ]
        promotional_strips = [
            {
                "id": row.strip_id,
                "name": strip.name,
                "prefix": strip.text_prefix,
                "text": strip.text_body,
                "background_color": strip.background_color or "#FFF1E8",
                "text_color": strip.text_color or "#7C2D12",
                "sort_order": row.sort_order,
            }
            for row, strip in (
                db.session.query(ProductPromotionalStrip, PromotionalStrip)
                .join(PromotionalStrip, PromotionalStrip.id == ProductPromotionalStrip.strip_id)
                .filter(
                    ProductPromotionalStrip.product_id == product_id,
                    PromotionalStrip.is_active.is_(True),
                )
                .order_by(ProductPromotionalStrip.sort_order, ProductPromotionalStrip.id)
                .all()
            )
        ]
        campaigns = [
            {
                "id": row.campaign_id,
                "name": campaign.name,
                "badge": {"id": campaign.badge_id} if campaign.badge_id else None,
            }
            for row, campaign in (
                db.session.query(CampaignProduct, Campaign)
                .join(Campaign, Campaign.id == CampaignProduct.campaign_id)
                .filter(
                    CampaignProduct.product_id == product_id,
                    Campaign.status == "active",
                )
                .order_by(CampaignProduct.sort_order, CampaignProduct.id)
                .all()
            )
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
        color_reference_rows = (
            db.session.query(ProductColorReference, Color)
            .join(Color, Color.id == ProductColorReference.color_id)
            .filter(ProductColorReference.product_id == product_id, Color.is_active.is_(True))
            .order_by(ProductColorReference.sort_order, ProductColorReference.id)
            .all()
        )
        reference_colors = [
            {
                "id": row.color_id,
                "name": color.name,
                "hex_code": color.hex_code,
                "swatch_asset_id": color.swatch_asset_id,
                "swatch_asset_url": (
                    db.session.get(MediaAsset, color.swatch_asset_id).url
                    if color.swatch_asset_id and db.session.get(MediaAsset, color.swatch_asset_id)
                    else None
                ),
            }
            for row, color in color_reference_rows
        ]
        size_reference_rows = (
            db.session.query(ProductSizeReference, Size)
            .join(Size, Size.id == ProductSizeReference.size_id)
            .filter(
                ProductSizeReference.product_id == product_id,
                Size.is_active.is_(True),
            )
            .order_by(ProductSizeReference.sort_order, ProductSizeReference.id)
            .all()
        )
        reference_sizes = [
            {
                "id": row.size_id,
                "label": size.label,
                "code": size.code,
                "group": size.group,
            }
            for row, size in size_reference_rows
        ]

        avg_rating, review_count = db.session.query(
            db.func.avg(Review.rating),
            db.func.count(Review.id),
        ).filter(
            Review.product_id == product_id,
            Review.status == "approved",
            Review.is_active.is_(True),
        ).one()
        rating_summary = {
            "average": round(float(avg_rating or 0), 2),
            "count": int(review_count or 0),
        }
        reviews_preview = [
            {
                "id": review.id,
                "rating": review.rating,
                "title": review.title,
                "body": review.body,
            }
            for review in Review.query.filter(
                Review.product_id == product_id,
                Review.status == "approved",
                Review.is_active.is_(True),
            ).order_by(Review.id.desc()).limit(8).all()
        ]
        side_category_circle_ids = [
            {"id": circle_id}
            for circle_id in CatalogService.list_product_side_category_circles(product_id)
        ]

        from ...models import SizeGuideRow

        def serialize_size_guide(guide, rows):
            return {
                "id": guide.id,
                "name": guide.name,
                "guide_type": guide.guide_type,
                "fit_type": guide.fit_type,
                "intro_text": guide.intro_text,
                "product_columns": guide.product_columns_json or [],
                "body_columns": guide.body_columns_json or [],
                "rows": [
                    {
                        "size_id": row.size_id,
                        "size_label": size.label,
                        "size_code": size.code,
                        "product_measurements": row.product_measurements or {},
                        "body_measurements": row.body_measurements or {},
                    }
                    for row, size in rows
                ],
            }

        selected_guide_rows = (
            db.session.query(ProductSizeGuideReference, SizeGuide)
            .join(SizeGuide, SizeGuide.id == ProductSizeGuideReference.guide_id)
            .filter(
                ProductSizeGuideReference.product_id == product_id,
                SizeGuide.is_active.is_(True),
            )
            .order_by(ProductSizeGuideReference.sort_order, SizeGuide.id)
            .all()
        )

        size_guides = []
        for _ref, guide in selected_guide_rows:
            guide_rows = (
                db.session.query(SizeGuideRow, Size)
                .join(Size, Size.id == SizeGuideRow.size_id)
                .filter(
                    SizeGuideRow.guide_id == guide.id,
                    Size.is_active.is_(True),
                )
                .order_by(SizeGuideRow.id)
                .all()
            )
            size_guides.append(serialize_size_guide(guide, guide_rows))

        # Backward compatibility: products that predate explicit guide assignment
        # still receive the best matching public guide rather than losing their
        # existing size-guide UI.
        if not size_guides:
            product_size_ids = {int(row.size_id) for row, _size in size_reference_rows}
            guides = SizeGuide.query.filter_by(is_active=True).order_by(SizeGuide.id).all()
            best_guide = None
            best_rows = []
            best_score = -1
            for guide in guides:
                guide_rows = (
                    db.session.query(SizeGuideRow, Size)
                    .join(Size, Size.id == SizeGuideRow.size_id)
                    .filter(
                        SizeGuideRow.guide_id == guide.id,
                        Size.is_active.is_(True),
                    )
                    .order_by(SizeGuideRow.id)
                    .all()
                )
                score = sum(1 for row, _size in guide_rows if int(row.size_id) in product_size_ids)
                if guide_rows and (
                    score > best_score
                    or (best_guide is None and score == best_score)
                ):
                    best_guide = guide
                    best_rows = guide_rows
                    best_score = score
            if best_guide is not None:
                size_guides.append(serialize_size_guide(best_guide, best_rows))

        guide_payload = size_guides[0] if size_guides else None


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
        product_card_global = CatalogService.product_card_display_settings()
        product_card_effective = CatalogService.product_card_display_settings(product_id)
        product_card_overrides = dict((display.card_overrides_json or {}) if display else {})
        delivery_badges = list((display.delivery_badges_json or []) if display else [])
        recommendation_settings = dict((display.recommendation_settings_json or {}) if display else {})
        active_trend_badges = []
        trend_rows = (
            db.session.query(TrendProduct, Trend, Hashtag)
            .join(Trend, Trend.id == TrendProduct.trend_id)
            .join(Hashtag, Hashtag.id == Trend.hashtag_id)
            .filter(
                TrendProduct.product_id == product_id,
                Trend.is_active.is_(True),
                Trend.status == "active",
                Hashtag.is_active.is_(True),
            )
            .order_by(TrendProduct.slot, Trend.id.desc(), TrendProduct.slot)
            .all()
        )
        for trend_product, trend, hashtag in trend_rows:
            if CatalogService.is_trend_timer_expired(trend):
                continue
            active_trend_badges.append({
                "id": trend.id,
                "hashtag": {
                    "id": hashtag.id,
                    "name": hashtag.name,
                    "slug": hashtag.slug,
                    "display_name": hashtag.display_name or f"#{hashtag.name}",
                },
                "text": trend.overlay_text or CatalogService.product_card_display_settings().get("trend_badge_text", "Trends"),
                "promo_text": trend.promo_text,
                "settings": {
                    **CatalogService.product_card_display_settings(),
                    **(trend_product.settings_json if isinstance(trend_product.settings_json, dict) else {}),
                    **(trend.settings_json if isinstance(trend.settings_json, dict) else {}),
                },
            })
        shipping_policy = (
            db.session.get(ShippingPolicy, policies.shipping_policy_id)
            if policies and policies.shipping_policy_id else None
        )
        return_policy = (
            db.session.get(ReturnPolicy, policies.return_policy_id)
            if policies and policies.return_policy_id else None
        )
        warranty_policy = (
            db.session.get(WarrantyPolicy, policies.warranty_policy_id)
            if policies and policies.warranty_policy_id else None
        )
        basics_ready = bool(
            (product.sku or "").strip()
            and (product.name or "").strip()
            and product.base_price is not None
            and product.base_price >= 0
        )
        active_variant_count = ProductVariant.query.filter_by(
            product_id=product_id,
            is_active=True,
        ).count()
        return {
            "product": CatalogService._serialize_product(product),
            "categories": categories,
            "root_category_ids": sorted(root_category_ids),
            "options": options,
            "variants": variants,
            "media": media,
            "badges": badges,
            "hashtags": hashtags,
            "promotional_strips": promotional_strips,
            "campaigns": campaigns,
            "reference_colors": reference_colors,
            "reference_sizes": reference_sizes,
            "size_guides": size_guides,
            "size_guide": guide_payload,
            "side_category_circles": side_category_circle_ids,
            "rating_summary": rating_summary,
            "reviews_preview": reviews_preview,
            "product_card_global_settings": product_card_global,
            "product_card_settings": product_card_effective,
            "product_card_overrides": product_card_overrides,
            "product_detail_settings": CatalogService.product_detail_settings(),
            "delivery_badges": delivery_badges,
            "recommendation_settings": recommendation_settings,
            "trend_badges": active_trend_badges,
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
                "shipping": {
                    "name": shipping_policy.name,
                    "free_shipping_enabled": bool(shipping_policy.free_shipping_enabled),
                    "min_order_amount": str(shipping_policy.min_order_amount) if shipping_policy.min_order_amount is not None else None,
                    "promo_text": shipping_policy.promo_text,
                    "delivery_window": shipping_policy.delivery_window,
                } if shipping_policy else None,
                "return": {
                    "name": return_policy.name,
                    "return_window_days": return_policy.return_window_days,
                    "conditions": return_policy.conditions,
                    "fee_rule": return_policy.fee_rule,
                    "refund_method": return_policy.refund_method,
                } if return_policy else None,
                "warranty": {
                    "name": warranty_policy.name,
                    "duration_days": warranty_policy.duration_days,
                    "coverage": warranty_policy.coverage,
                    "exclusions": warranty_policy.exclusions,
                    "claim_method": warranty_policy.claim_method,
                } if warranty_policy else None,
            },
            "publishable": bool(basics_ready and categories and active_variant_count and media),
            "steps": {
                "basics": basics_ready,
                "categories": bool(categories),
                "side-categories": bool(side_category_circle_ids),
                "media": bool(media),
                "options": bool(reference_colors or reference_sizes or options),
                "variants": bool(active_variant_count),
                "inventory": bool(inventory),
                "publish": bool(basics_ready and categories and active_variant_count and media),
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
    def product_detail_settings():
        """Global customer-facing product-detail layout, typography and policy controls."""
        import json
        defaults = {
            "detail_groups": [
                {
                    "title": "هوية المنتج والسعر",
                    "items": ["trend", "name", "rating", "brand", "price", "promotions", "description", "badges"],
                    "show": True,
                },
                {
                    "title": "الألوان والمقاسات",
                    "items": ["thumbs", "colors", "sizes", "size_guide"],
                    "show": True,
                },
                {
                    "title": "التوصيل والسياسات",
                    "items": ["delivery", "policies"],
                    "show": True,
                },
                {
                    "title": "تفاصيل المنتج والتوفر",
                    "items": ["details", "stock"],
                    "show": True,
                },
                {
                    "title": "التقييمات والمراجعات",
                    "items": ["reviews"],
                    "show": True,
                },
                {
                    "title": "اقتراحات التسوق",
                    "items": ["related"],
                    "show": True,
                },
            ],
            "layout_mode": "shein",
            "group_show_titles": False,
            "group_background_color": "#FFFFFF",
            "group_border_color": "#F0F0F0",
            "group_border_width": 0.0,
            "group_radius": 0,
            "group_margin_top": 0,
            "group_padding_horizontal": 0,
            "group_padding_vertical": 0,
            "group_divider": "subtle",
            "group_divider_color": "#EEEEEE",
            "group_divider_width": 0.7,
            "trend_show": True,
            "trend_title": "ترندات",
            "trend_show_hashtag": True,
            "trend_show_promo": False,
            "trend_show_arrow": False,
            "trend_title_font_size": 17,
            "trend_hashtag_font_size": 12,
            "trend_height": 46,
            "trend_padding_horizontal": 12,
            "trend_background_color": "#F2E8FF",
            "trend_title_color": "#8B5CF6",
            "trend_hashtag_color": "#7C3AED",
            "trend_arrow_color": "#7C3AED",
            "trend_divider_color": "#E9D5FF",
            "variant_background_color": "#FFFFFF",
            "variant_padding_horizontal": 12,
            "variant_padding_vertical": 10,
            "variant_row_gap": 12,
            "variant_divider_show": True,
            "variant_divider_color": "#EEEEEE",
            "variant_divider_width": 0.7,
            "color_presentation": "image_circle",
            "color_shape": "circle",
            "color_image_size": 48,
            "color_swatches_size": 30,
            "color_gap": 8,
            "color_label_font_size": 9,
            "color_show_label": True,
            "color_show_hot": True,
            "color_show_quantity": False,
            "color_quantity_text": "{qty} متوفر",
            "color_quantity_only_when_low": True,
            "color_quantity_threshold": 7,
            "color_selected_border_width": 2,
            "color_selected_border_color": "#111111",
            "color_border_color": "#DDDDDD",
            "color_max_visible": 12,
            "size_height": 48,
            "size_min_width": 56,
            "size_border_radius": 2,
            "size_inventory_badge_show": True,
            "size_inventory_badge_font_size": 8,
            "size_inventory_badge_background": "#FF5A3D",
            "size_inventory_badge_text": "#FFFFFF",
            "size_inventory_badge_text_template": "{qty} left",
            "size_inventory_badge_show_out_of_stock": False,
            "size_inventory_badge_out_of_stock_text": "نفد",
            "size_inventory_only_when_low": True,
            "size_inventory_threshold": 7,
            "size_label_alignment": "center",
            "size_row_gap": 7,
            "size_selected_border_width": 1,
            "size_divider_show": False,
            "size_divider_color": "#EEEEEE",
            "size_divider_width": 0.7,
            "size_tools_show": True,
            "size_tools_divider_show": False,
            "size_tools_font_size": 10,
            "size_tools_icon_size": 16,
            "size_tools_color": "#111111",
            "size_tools_gap": 12,
            "delivery_location_show": True,
            "delivery_location_mode": "fixed",
            "delivery_location_title": "الشحن إلى",
            "delivery_location_country": "Saudi Arabia",
            "delivery_location_region": "الرياض",
            "delivery_location_city": "الرياض",
            "delivery_location_font_size": 12,
            "delivery_location_icon_size": 18,
            "delivery_location_color": "#111111",
            "delivery_row_height": 54,
            "delivery_row_title_font_size": 11,
            "delivery_row_subtitle_font_size": 9.5,
            "delivery_row_icon_size": 19,
            "delivery_row_divider_show": True,
            "delivery_row_divider_color": "#EEEEEE",
            "delivery_row_divider_width": 0.7,
            "policy_row_height": 50,
            "policy_row_title_font_size": 11,
            "policy_row_subtitle_font_size": 9.5,
            "policy_row_icon_size": 19,
            "policy_row_divider_show": True,
            "policy_row_divider_color": "#EEEEEE",
            "policy_row_divider_width": 0.7,
            "policy_show_arrows": True,
            "policy_show_dialog": True,
            "detail_order": [
                "badges", "gallery", "thumbs", "trend", "price", "promotions",
                "name", "description", "rating", "brand", "colors", "sizes", "size_guide",
                "details", "stock", "delivery", "policies", "reviews", "related",
            ],
            "gallery_show": True,
            "gallery_ratio": 0.78,
            "thumbs_show": True,
            "thumbs_size": 62,
            "thumbs_height": 70,
            "thumbs_gap": 6,
            "thumbs_radius": 4,
            "thumbs_border_width": 1.5,

            "badges_show": True,
            "badges_gap": 5,

            "name_show": True,
            "name_font_size": 20.0,
            "name_font_weight": 800,
            "name_max_lines": 4,
            "name_color": "#111111",

            "description_show": True,
            "description_font_size": 10.5,
            "description_max_lines": 3,
            "description_color": "#6b7280",

            "price_show": True,
            "price_font_size": 22.0,
            "price_font_weight": 900,
            "price_color": "#111111",
            "show_compare_price": True,
            "compare_price_font_size": 10.0,
            "compare_price_color": "#9ca3af",
            "compare_price_text_decoration": "line_through",
            "show_currency": True,
            "currency_font_size": 10.5,
            "currency_color": "#111111",
            "price_text_show": False,
            "price_text": "السعر الحالي",
            "price_text_font_size": 9.0,
            "price_text_color": "#6b7280",

            "brand_show": True,
            "brand_font_size": 10.0,
            "brand_font_weight": 800,
            "brand_color": "#6b7280",

            "colors_show": True,
            "colors_size": 38,
            "colors_label_font_size": 8.5,
            "colors_gap": 9,
            "colors_run_gap": 8,
            "colors_selected_border_width": 2,

            "sizes_show": True,
            "sizes_font_size": 10,
            "sizes_padding_horizontal": 12,
            "sizes_padding_vertical": 9,
            "sizes_gap": 7,
            "sizes_background_color": "#ffffff",
            "sizes_text_color": "#000000",
            "sizes_selected_background_color": "#000000",
            "sizes_selected_text_color": "#ffffff",
            "sizes_border_color": "#d8d8d8",

            "size_guide_show": True,
            "size_guide_font_size": 10,
            "size_guide_color": "#111111",
            "size_guide_background_color": "#ffffff",
            "size_guide_navigation_mode": "tabs",
            "size_guide_show_product_measurements": True,
            "size_guide_show_body_measurements": True,

            "details_show": True,
            "details_title_font_size": 13,
            "details_title_color": "#111111",
            "details_text_font_size": 10.5,
            "details_text_color": "#4b5563",
            "details_background_color": "#ffffff",

            "stock_show": False,
            "stock_font_size": 10,
            "stock_text_color": "#15803D",
            "stock_inline_show": True,
            "stock_inline_position": "name",
            "stock_inline_text": "متوفر",
            "stock_inline_out_text": "غير متوفر",
            "stock_inline_color": "#15803D",

            "delivery_show": True,
            "delivery_font_size": 9,
            "delivery_color": "#111111",

            "policies_show": True,
            "policy_order": ["shipping", "returns", "warranty", "payment"],
            "policy_button_height": 52,
            "policy_button_radius": 8,
            "policy_button_gap": 6,
            "policy_button_font_size": 9,
            "shipping_button_color": "#111111",
            "shipping_button_text_color": "#ffffff",
            "returns_button_color": "#f3f4f6",
            "returns_button_text_color": "#111111",
            "warranty_button_color": "#f3f4f6",
            "warranty_button_text_color": "#111111",
            "payment_button_color": "#f3f4f6",
            "payment_button_text_color": "#111111",

            "rating_show": True,
            "rating_icon_size": 14,
            "rating_font_size": 10,
            "rating_review_count_show": True,
            "rating_review_count_font_size": 8,
            "rating_color": "#ffb400",

            "reviews_show": True,
            "reviews_title_font_size": 13,
            "reviews_color": "#111111",

            "related_show": True,
            "related_title_font_size": 13,
        }
        row = AppSetting.query.filter_by(
            group_code="storefront",
            key="product_detail_settings",
        ).first()
        custom = {}
        if row and row.value:
            try:
                decoded = json.loads(row.value)
                if isinstance(decoded, dict):
                    custom = decoded
            except (TypeError, ValueError):
                custom = {}
        merged = {**defaults, **custom}

        allowed_detail_groups = {
            "badges", "gallery", "thumbs", "trend", "price", "promotions",
            "name", "description", "rating", "brand", "colors", "sizes",
            "size_guide", "details", "stock", "delivery", "policies",
            "reviews", "related",
        }

        raw_groups = merged.get("detail_groups")
        normalized_groups = []
        if isinstance(raw_groups, list):
            for raw_group in raw_groups:
                if not isinstance(raw_group, dict):
                    continue
                title = str(raw_group.get("title") or "").strip()[:80] or "قسم تفاصيل"
                raw_items = raw_group.get("items")
                if not isinstance(raw_items, list):
                    raw_items = []
                items = []
                for key in raw_items:
                    key = str(key)
                    if key in allowed_detail_groups and key not in items:
                        items.append(key)
                if items:
                    normalized_groups.append({
                        "title": title,
                        "items": items,
                        "show": raw_group.get("show") is not False,
                    })

        seen = set()
        for group in normalized_groups:
            clean_items = []
            for key in group["items"]:
                if key not in seen:
                    clean_items.append(key)
                    seen.add(key)
            group["items"] = clean_items
        normalized_groups = [g for g in normalized_groups if g["items"]]

        for key in defaults["detail_order"]:
            # The main gallery stays above the boxed detail groups by default.
            if key == "gallery":
                continue
            if key not in seen:
                normalized_groups.append({
                    "title": "قسم تفاصيل",
                    "items": [key],
                    "show": True,
                })
                seen.add(key)

        if not normalized_groups:
            normalized_groups = [dict(g) for g in defaults["detail_groups"]]

        merged["detail_groups"] = normalized_groups

        allowed_order = [
            "badges", "gallery", "thumbs", "trend", "price", "promotions",
            "name", "description", "rating", "brand", "colors", "sizes", "size_guide",
            "details", "stock", "delivery", "policies", "reviews", "related",
        ]
        raw_order = merged.get("detail_order")
        if not isinstance(raw_order, list):
            raw_order = list(defaults["detail_order"])
        normalized_order = []
        for key in raw_order:
            key = str(key)
            if key in allowed_order and key not in normalized_order:
                normalized_order.append(key)
        for key in allowed_order:
            if key not in normalized_order:
                normalized_order.append(key)
        merged["detail_order"] = normalized_order

        allowed_policy_order = ["shipping", "returns", "warranty", "payment"]
        raw_policy_order = merged.get("policy_order")
        if not isinstance(raw_policy_order, list):
            raw_policy_order = list(defaults["policy_order"])
        normalized_policy_order = []
        for key in raw_policy_order:
            key = str(key)
            if key in allowed_policy_order and key not in normalized_policy_order:
                normalized_policy_order.append(key)
        for key in allowed_policy_order:
            if key not in normalized_policy_order:
                normalized_policy_order.append(key)
        merged["policy_order"] = normalized_policy_order

        def number(key, low, high, integer=False):
            try:
                value = float(merged.get(key, defaults[key]))
            except (TypeError, ValueError):
                value = float(defaults[key])
            value = max(low, min(high, value))
            return int(round(value)) if integer else value

        def flag(key):
            value = merged.get(key)
            return value if isinstance(value, bool) else bool(value)

        def color(key):
            value = str(merged.get(key) or defaults[key]).strip()
            if not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
                value = defaults[key]
            return value

        for key, low, high, integer in (
            ("group_border_width", 0, 4, False),
            ("group_radius", 0, 24, True),
            ("group_margin_top", 0, 24, True),
            ("group_padding_horizontal", 0, 24, True),
            ("group_padding_vertical", 0, 24, True),
            ("group_divider_width", 0, 3, False),
            ("trend_title_font_size", 9, 28, False),
            ("trend_hashtag_font_size", 7, 20, False),
            ("trend_height", 28, 80, True),
            ("trend_padding_horizontal", 4, 24, True),
            ("variant_padding_horizontal", 0, 24, True),
            ("variant_padding_vertical", 0, 24, True),
            ("variant_row_gap", 0, 24, True),
            ("variant_divider_width", 0, 3, False),
            ("color_image_size", 30, 72, True),
            ("color_swatches_size", 18, 64, True),
            ("color_gap", 0, 18, True),
            ("color_label_font_size", 6, 16, False),
            ("color_quantity_threshold", 1, 30, True),
            ("color_selected_border_width", 0, 5, False),
            ("size_height", 34, 68, True),
            ("size_min_width", 38, 110, True),
            ("size_border_radius", 0, 16, True),
            ("size_inventory_badge_font_size", 6, 14, False),
            ("size_inventory_threshold", 1, 30, True),
            ("size_row_gap", 0, 18, True),
            ("size_selected_border_width", 0, 4, False),
            ("size_divider_width", 0, 3, False),
            ("size_tools_font_size", 7, 18, False),
            ("size_tools_icon_size", 10, 26, True),
            ("size_tools_gap", 0, 24, True),
            ("delivery_location_font_size", 8, 18, False),
            ("delivery_location_icon_size", 12, 28, True),
            ("delivery_row_height", 40, 76, True),
            ("delivery_row_title_font_size", 8, 18, False),
            ("delivery_row_subtitle_font_size", 7, 16, False),
            ("delivery_row_icon_size", 12, 28, True),
            ("delivery_row_divider_width", 0, 3, False),
            ("policy_row_height", 40, 76, True),
            ("policy_row_title_font_size", 8, 18, False),
            ("policy_row_subtitle_font_size", 7, 16, False),
            ("policy_row_icon_size", 12, 28, True),
            ("policy_row_divider_width", 0, 3, False),
            ("thumbs_size", 40, 110, True),
            ("thumbs_height", 45, 120, True),
            ("thumbs_gap", 0, 18, True),
            ("thumbs_radius", 0, 20, True),
            ("thumbs_border_width", 0, 4, False),
            ("badges_gap", 0, 20, True),
            ("name_font_size", 14, 32, False),
            ("name_font_weight", 400, 900, True),
            ("name_max_lines", 2, 6, True),
            ("description_font_size", 7, 18, False),
            ("description_max_lines", 1, 5, True),
            ("price_font_size", 14, 34, False),
            ("price_font_weight", 400, 900, True),
            ("compare_price_font_size", 7, 20, False),
            ("currency_font_size", 7, 20, False),
            ("price_text_font_size", 7, 18, False),
            ("brand_font_size", 7, 18, False),
            ("brand_font_weight", 400, 900, True),
            ("colors_size", 24, 64, True),
            ("colors_label_font_size", 6, 16, False),
            ("colors_gap", 0, 18, True),
            ("colors_run_gap", 0, 18, True),
            ("colors_selected_border_width", 0, 4, False),
            ("sizes_font_size", 7, 18, False),
            ("sizes_padding_horizontal", 4, 24, True),
            ("sizes_padding_vertical", 3, 18, True),
            ("sizes_gap", 0, 16, True),
            ("size_guide_font_size", 7, 18, False),
            ("details_title_font_size", 9, 20, False),
            ("details_text_font_size", 8, 18, False),
            ("stock_font_size", 7, 18, False),
            ("delivery_font_size", 7, 18, False),
            ("policy_button_height", 36, 76, True),
            ("policy_button_radius", 0, 24, True),
            ("policy_button_gap", 0, 16, True),
            ("policy_button_font_size", 7, 18, False),
            ("rating_icon_size", 7, 28, False),
            ("rating_font_size", 7, 20, False),
            ("rating_review_count_font_size", 6, 18, False),
            ("reviews_title_font_size", 9, 20, False),
            ("related_title_font_size", 9, 20, False),
        ):
            merged[key] = number(key, low, high, integer)

        merged["group_show_titles"] = flag("group_show_titles")
        merged["color_show_quantity"] = flag("color_show_quantity")
        merged["color_quantity_only_when_low"] = flag("color_quantity_only_when_low")
        merged["size_inventory_badge_show_out_of_stock"] = flag("size_inventory_badge_show_out_of_stock")
        merged["stock_inline_show"] = flag("stock_inline_show")
        merged["trend_show"] = flag("trend_show")
        merged["trend_show_hashtag"] = flag("trend_show_hashtag")
        merged["trend_show_promo"] = flag("trend_show_promo")
        merged["trend_show_arrow"] = flag("trend_show_arrow")
        merged["variant_divider_show"] = flag("variant_divider_show")
        merged["color_show_label"] = flag("color_show_label")
        merged["color_show_hot"] = flag("color_show_hot")
        merged["size_inventory_badge_show"] = flag("size_inventory_badge_show")
        merged["size_inventory_only_when_low"] = flag("size_inventory_only_when_low")
        merged["size_tools_show"] = flag("size_tools_show")
        merged["size_tools_divider_show"] = flag("size_tools_divider_show")
        merged["size_divider_show"] = flag("size_divider_show")
        merged["delivery_location_show"] = flag("delivery_location_show")
        merged["delivery_row_divider_show"] = flag("delivery_row_divider_show")
        merged["policy_row_divider_show"] = flag("policy_row_divider_show")
        merged["policy_show_arrows"] = flag("policy_show_arrows")
        merged["policy_show_dialog"] = flag("policy_show_dialog")
        merged["gallery_show"] = flag("gallery_show")
        merged["thumbs_show"] = flag("thumbs_show")
        merged["badges_show"] = flag("badges_show")
        merged["name_show"] = flag("name_show")
        merged["description_show"] = flag("description_show")
        merged["price_show"] = flag("price_show")
        merged["show_compare_price"] = flag("show_compare_price")
        merged["show_currency"] = flag("show_currency")
        merged["price_text_show"] = flag("price_text_show")
        merged["brand_show"] = flag("brand_show")
        merged["colors_show"] = flag("colors_show")
        merged["sizes_show"] = flag("sizes_show")
        merged["size_guide_show"] = flag("size_guide_show")
        merged["size_guide_show_product_measurements"] = flag("size_guide_show_product_measurements")
        merged["size_guide_show_body_measurements"] = flag("size_guide_show_body_measurements")
        merged["details_show"] = flag("details_show")
        merged["stock_show"] = flag("stock_show")
        merged["delivery_show"] = flag("delivery_show")
        merged["policies_show"] = flag("policies_show")
        merged["rating_show"] = flag("rating_show")
        merged["rating_review_count_show"] = flag("rating_review_count_show")
        merged["reviews_show"] = flag("reviews_show")
        merged["related_show"] = flag("related_show")

        merged["gallery_ratio"] = max(.56, min(1.05, float(merged.get("gallery_ratio", defaults["gallery_ratio"]))))
        merged["compare_price_text_decoration"] = (
            merged["compare_price_text_decoration"]
            if merged["compare_price_text_decoration"] in {"line_through", "none"}
            else defaults["compare_price_text_decoration"]
        )
        merged["layout_mode"] = merged.get("layout_mode") if merged.get("layout_mode") in {"shein", "boxed"} else "shein"
        merged["size_guide_navigation_mode"] = (
            merged.get("size_guide_navigation_mode")
            if merged.get("size_guide_navigation_mode") in {"tabs", "swipe"}
            else "tabs"
        )
        merged["group_divider"] = merged.get("group_divider") if merged.get("group_divider") in {"none", "subtle", "strong"} else "subtle"
        merged["color_presentation"] = merged.get("color_presentation") if merged.get("color_presentation") in {"image", "circle", "image_circle"} else "image_circle"
        merged["color_shape"] = merged.get("color_shape") if merged.get("color_shape") in {"circle", "square"} else "circle"
        merged["size_label_alignment"] = merged.get("size_label_alignment") if merged.get("size_label_alignment") in {"left", "center", "right"} else "center"
        merged["stock_inline_position"] = merged.get("stock_inline_position") if merged.get("stock_inline_position") in {"name", "color", "none"} else "name"
        merged["delivery_location_mode"] = merged.get("delivery_location_mode") if merged.get("delivery_location_mode") in {"fixed", "customer_city"} else "fixed"
        merged["color_quantity_text"] = str(merged.get("color_quantity_text") or defaults["color_quantity_text"])[:80]
        merged["size_inventory_badge_text_template"] = str(merged.get("size_inventory_badge_text_template") or defaults["size_inventory_badge_text_template"])[:80]
        merged["size_inventory_badge_out_of_stock_text"] = str(merged.get("size_inventory_badge_out_of_stock_text") or defaults["size_inventory_badge_out_of_stock_text"])[:40]
        merged["stock_inline_text"] = str(merged.get("stock_inline_text") or defaults["stock_inline_text"])[:40]
        merged["stock_inline_out_text"] = str(merged.get("stock_inline_out_text") or defaults["stock_inline_out_text"])[:40]
        merged["delivery_location_title"] = str(merged.get("delivery_location_title") or defaults["delivery_location_title"])[:80]
        merged["delivery_location_country"] = str(merged.get("delivery_location_country") or defaults["delivery_location_country"])[:100]
        merged["delivery_location_region"] = str(merged.get("delivery_location_region") or defaults["delivery_location_region"])[:100]
        merged["delivery_location_city"] = str(merged.get("delivery_location_city") or defaults["delivery_location_city"])[:100]
        merged["price_text"] = str(merged.get("price_text") or defaults["price_text"])[:80]

        for key in (
            "group_background_color", "group_border_color", "group_divider_color",
            "trend_background_color", "trend_title_color", "trend_hashtag_color", "trend_arrow_color", "trend_divider_color",
            "variant_background_color", "variant_divider_color",
            "color_selected_border_color", "color_border_color",
            "size_inventory_badge_background", "size_inventory_badge_text",
            "stock_inline_color",
            "size_divider_color", "size_tools_color",
            "delivery_location_color", "delivery_row_divider_color",
            "policy_row_divider_color",
            "name_color", "description_color", "price_color", "compare_price_color", "currency_color",
            "price_text_color", "brand_color",
            "sizes_background_color", "sizes_text_color",
            "sizes_selected_background_color", "sizes_selected_text_color",
            "sizes_border_color", "size_guide_color", "size_guide_background_color",
            "details_title_color", "details_text_color", "details_background_color",
            "stock_text_color", "delivery_color",
            "shipping_button_color", "shipping_button_text_color",
            "returns_button_color", "returns_button_text_color",
            "warranty_button_color", "warranty_button_text_color",
            "payment_button_color", "payment_button_text_color",
            "rating_color",
            "reviews_color",
        ):
            merged[key] = color(key)
        return merged

    @staticmethod
    def merge_product_card_settings(global_settings, display_row=None):
        merged = dict(global_settings or {})
        overrides = getattr(display_row, "card_overrides_json", None) if display_row else {}
        if isinstance(overrides, dict):
            merged.update(overrides)
        return merged

    @staticmethod
    def product_card_display_settings(product_id=None):
        """Global storefront product-card decoration/layout controlled by AppSetting."""
        import json
        defaults = {
            "card_background_color": "#ffffff",
            "card_background_opacity": 1.0,
            "card_radius": 4,
            "image_to_content_gap": 4,
            "content_vertical_gap": 2,
            "show_name": True,
            "name_font_size": 11,
            "name_font_weight": 600,
            "name_color": "#111111",
            "name_background_color": "#ffffff",
            "name_background_opacity": 1.0,
            "name_max_lines": 3,
            "name_overflow": "wrap",
            "show_short_description": False,
            "short_description_position": "after_name",
            "short_description_font_size": 9,
            "short_description_font_weight": 500,
            "short_description_color": "#6b7280",
            "short_description_background_color": "#ffffff",
            "short_description_background_opacity": 0.0,
            "short_description_max_lines": 1,
            "show_price": True,
            "price_font_size": 14,
            "price_font_weight": 900,
            "price_color": "#111111",
            "price_background_color": "#ffffff",
            "price_background_opacity": 1.0,
            "show_compare_price": True,
            "compare_price_font_size": 10,
            "compare_price_font_weight": 500,
            "compare_price_color": "#8b9198",
            "compare_price_background_color": "#ffffff",
            "compare_price_background_opacity": 1.0,
            "compare_price_text_decoration": "line_through",
            "show_currency": True,
            "currency_font_size": 10,
            "currency_font_weight": 800,
            "currency_color": "#111111",
            "currency_background_color": "#ffffff",
            "currency_background_opacity": 1.0,
            "show_size": False,
            "size_font_size": 9,
            "size_font_weight": 600,
            "size_color": "#6b7280",
            "size_background_color": "#f5f5f5",
            "size_background_opacity": 1.0,
            "show_brand": True,
            "brand_position": "top_left",
            "brand_background_color": "#111827",
            "brand_text_color": "#ffffff",
            "brand_font_size": 8,
            "brand_radius": 4,
            "show_product_badges": True,
            "product_badge_position": "top_right",
            "product_badge_font_size": 8,
            "product_badge_radius": 3,
            "product_badge_max": 4,
            "show_trend_badge": True,
            "trend_badge_text": "Trends",
            "trend_badge_background_color": "#8b5cf6",
            "trend_badge_text_color": "#ffffff",
            "trend_badge_font_size": 8,
            "trend_badge_radius": 3,
            "show_trend_hashtag": True,
            "trend_hashtag_text_color": "#7c3aed",
            "trend_hashtag_background_color": "#f0e6ff",
            "trend_hashtag_use_background": True,
            "trend_hashtag_font_size": 8,
            "trend_hashtag_font_weight": 800,
            "trend_show_arrow": True,
            "trend_arrow_text": "‹",
            "trend_arrow_color": "#7c3aed",
            "trend_ribbon_gap": 3,
            "discount_badge_background_color": "#DC2626",
            "discount_badge_text_color": "#FFFFFF",
            "discount_badge_font_size": 9,
            "discount_badge_font_weight": 900,
            "discount_badge_radius": 4,
            "colors_show": True,
            "colors_position": "bottom_right",
            "colors_direction": "vertical",
            "colors_size": 13,
            "colors_gap": 2,
            "colors_max": 6,
            "colors_container_size": 16,
            "colors_border_width": 1,
            "meta_show": True,
            "meta_position": "top_right",
            "meta_font_size": 7.5,
            "meta_background_color": "#f4f4f4",
            "meta_text_color": "#111111",
            "meta_radius": 3,
            "meta_padding_horizontal": 4,
            "meta_padding_vertical": 2,

            # Rating inside the product card.
            "rating_show": True,
            "rating_position": "after_price",
            "rating_alignment": "right",
            "rating_font_size": 8.5,
            "rating_icon_size": 12.5,
            "rating_color": "#ffb400",
            "rating_review_count_show": True,
            "rating_review_count_font_size": 8,

            # Quick-add button on the product image.
            "quick_add_show": True,
            "quick_add_icon": "shopping_bag_outlined",
            "quick_add_size": 32,
            "quick_add_position": "bottom_left",
            "quick_add_radius": 16,
            "quick_add_background_color": "#ffffff",
            "quick_add_icon_color": "#111111",
            "quick_add_opacity": 0.93,

            # Product-image swipe animation.
            "image_flip_effect": "slide",
            "image_flip_duration_ms": 260,
        }
        row = AppSetting.query.filter_by(
            group_code="storefront",
            key="product_card_settings",
        ).first()
        custom = {}
        if row and row.value:
            try:
                decoded = json.loads(row.value)
                if isinstance(decoded, dict):
                    custom = decoded
            except (TypeError, ValueError):
                custom = {}

        merged = {**defaults, **custom}

        # Product-level overrides are sparse. Any key not overridden inherits
        # the current global setting, so changing the global theme continues
        # to affect every product that has no override for that key.
        if product_id is not None:
            row = db.session.get(ProductDisplaySettings, int(product_id))
            overrides = row.card_overrides_json if row else {}
            if isinstance(overrides, dict):
                merged.update(overrides)

        def _number(key, low, high, integer=False):
            raw = merged.get(key)
            try:
                value = float(raw)
            except (TypeError, ValueError):
                value = float(defaults[key])
            value = max(low, min(high, value))
            return int(round(value)) if integer else value

        def _bool(key):
            value = merged.get(key)
            return value if isinstance(value, bool) else bool(value)

        def _color(key):
            value = str(merged.get(key) or defaults[key]).strip()
            import re
            return value if re.fullmatch(r"#[0-9a-fA-F]{6}", value) else defaults[key]

        for key, low, high, integer in (
            ("card_background_opacity", 0, 1, False),
            ("card_radius", 0, 30, False),
            ("name_font_size", 7, 24, False),
            ("name_font_weight", 300, 900, True),
            ("name_max_lines", 1, 6, True),
            ("short_description_font_size", 7, 18, False),
            ("short_description_font_weight", 300, 900, True),
            ("short_description_max_lines", 1, 4, True),
            ("short_description_background_opacity", 0, 1, False),
            ("rating_font_size", 6, 18, False),
            ("rating_icon_size", 7, 24, False),
            ("rating_review_count_font_size", 6, 18, False),
            ("quick_add_size", 22, 64, False),
            ("quick_add_radius", 0, 32, True),
            ("quick_add_opacity", 0, 1, False),
            ("image_flip_duration_ms", 80, 1200, True),
            ("price_font_size", 9, 28, False),
            ("price_font_weight", 300, 900, True),
            ("price_background_opacity", 0, 1, False),
            ("compare_price_font_size", 7, 20, False),
            ("compare_price_font_weight", 300, 900, True),
            ("compare_price_background_opacity", 0, 1, False),
            ("currency_font_size", 7, 20, False),
            ("currency_font_weight", 300, 900, True),
            ("currency_background_opacity", 0, 1, False),
            ("size_font_size", 7, 18, False),
            ("size_font_weight", 300, 900, True),
            ("size_background_opacity", 0, 1, False),
            ("brand_font_size", 6, 18, False),
            ("brand_radius", 0, 16, True),
            ("product_badge_font_size", 6, 18, False),
            ("product_badge_radius", 0, 16, True),
            ("product_badge_max", 1, 8, True),
            ("trend_badge_font_size", 6, 18, False),
            ("trend_badge_radius", 0, 16, True),
            ("trend_hashtag_font_size", 6, 18, False),
            ("trend_hashtag_font_weight", 400, 900, True),
            ("trend_ribbon_gap", 0, 12, True),
            ("discount_badge_font_size", 6, 18, False),
            ("discount_badge_font_weight", 300, 900, True),
            ("discount_badge_radius", 0, 16, True),
            ("colors_size", 8, 24, True),
            ("colors_gap", 0, 10, True),
            ("colors_max", 1, 8, True),
            ("colors_container_size", 10, 28, True),
            ("colors_border_width", 0, 3, True),
            ("meta_font_size", 6, 18, False),
            ("meta_radius", 0, 16, True),
            ("meta_padding_horizontal", 0, 12, True),
            ("meta_padding_vertical", 0, 8, True),
        ):
            merged[key] = _number(key, low, high, integer)

        for key in (
            "show_name",
            "show_short_description",
            "show_price",
            "show_compare_price",
            "show_currency",
            "show_size",
            "show_brand",
            "show_product_badges",
            "show_trend_badge",
            "show_trend_hashtag",
            "trend_hashtag_use_background",
            "trend_show_arrow",
            "colors_show",
            "meta_show",
            "rating_show",
            "rating_review_count_show",
            "quick_add_show",
            "quick_add_transparent",
        ):
            merged[key] = _bool(key)

        for key in (
            "card_background_color",
            "name_color",
            "name_background_color",
            "short_description_color",
            "short_description_background_color",
            "price_color",
            "price_background_color",
            "compare_price_color",
            "compare_price_background_color",
            "currency_color",
            "currency_background_color",
            "size_color",
            "size_background_color",
            "brand_background_color",
            "brand_text_color",
            "trend_badge_background_color",
            "trend_badge_text_color",
            "discount_badge_background_color",
            "discount_badge_text_color",
            "trend_hashtag_text_color",
            "trend_hashtag_background_color",
            "trend_arrow_color",
            "meta_background_color",
            "meta_text_color",
            "rating_color",
            "quick_add_background_color",
            "quick_add_icon_color",
        ):
            merged[key] = _color(key)

        for key in (
            "brand_position",
            "product_badge_position",
            "colors_position",
            "colors_direction",
            "meta_position",
            "short_description_position",
            "rating_position",
            "rating_alignment",
            "quick_add_icon",
            "quick_add_position",
            "image_flip_effect",
            "name_overflow",
        ):
            merged[key] = str(merged.get(key) or defaults[key]).strip().lower()

        if merged["brand_position"] not in {"top_left", "top_right", "bottom_left", "bottom_right"}:
            merged["brand_position"] = defaults["brand_position"]
        allowed_badge_positions = {
            "top_left", "top_right", "bottom_left", "bottom_right",
            "above_image", "right_of_image",
            "before_name", "before_name_same_row", "before_name_new_row",
            "after_name", "after_name_same_row", "after_name_new_row",
            "before_description", "before_description_same_row", "before_description_new_row",
            "after_description", "after_description_same_row", "after_description_new_row",
            "below_description",
            "before_price", "before_price_same_row", "before_price_new_row",
            "after_price", "after_price_same_row", "after_price_new_row", "below_price",
            "before_details", "after_details", "after_details_same_row", "after_details_new_row",
            "first", "last",
        }
        if merged["product_badge_position"] not in allowed_badge_positions:
            merged["product_badge_position"] = defaults["product_badge_position"]
        if merged["colors_position"] not in {"top_left", "top_right", "bottom_left", "bottom_right"}:
            merged["colors_position"] = defaults["colors_position"]
        if merged["colors_direction"] not in {"horizontal", "vertical"}:
            merged["colors_direction"] = defaults["colors_direction"]
        if merged["meta_position"] not in {"top_left", "top_right", "bottom_left", "bottom_right"}:
            merged["meta_position"] = defaults["meta_position"]

        if merged["short_description_position"] not in {
            "before_name", "after_name", "before_price", "after_price", "end",
        }:
            merged["short_description_position"] = defaults["short_description_position"]

        if merged["rating_position"] not in {
            "before_name", "after_name", "before_price", "after_price", "end",
        }:
            merged["rating_position"] = defaults["rating_position"]
        if merged["rating_alignment"] not in {"right", "left"}:
            merged["rating_alignment"] = defaults["rating_alignment"]

        if merged["quick_add_position"] not in {
            "top_left", "top_right", "bottom_left", "bottom_right",
        }:
            merged["quick_add_position"] = defaults["quick_add_position"]

        if merged["quick_add_icon"] not in {
            "shopping_bag_outlined", "shopping_cart_outlined",
            "add_shopping_cart_outlined", "local_mall_outlined",
        }:
            merged["quick_add_icon"] = defaults["quick_add_icon"]

        if merged["image_flip_effect"] not in {"slide", "fade", "card_flip"}:
            merged["image_flip_effect"] = defaults["image_flip_effect"]

        if merged["name_overflow"] not in {"wrap", "ellipsis"}:
            merged["name_overflow"] = defaults["name_overflow"]

        for key, limit in (
            ("trend_badge_text", 40),
            ("trend_show_arrow", 1),
        ):
            if key == "trend_badge_text":
                merged[key] = str(merged.get(key) or defaults[key]).strip()[:limit]
        merged["trend_arrow_text"] = str(
            merged.get("trend_arrow_text") or defaults["trend_arrow_text"]
        ).strip()[:3] or defaults["trend_arrow_text"]

        return merged

    @staticmethod
    def _serialize_trend_product(product):
        media_rows = (
            db.session.query(ProductMedia, MediaAsset)
            .join(MediaAsset, MediaAsset.id == ProductMedia.asset_id)
            .filter(ProductMedia.product_id == product.id)
            .order_by(ProductMedia.sort_order, ProductMedia.id)
            .all()
        )
        images = [
            {
                "id": media.asset_id,
                "url": asset.url,
                "color_id": media.color_id,
                "width": asset.width,
                "height": asset.height,
            }
            for media, asset in media_rows
        ]
        brand = db.session.get(Brand, product.brand_id) if product.brand_id else None
        primary_image = images[0]["url"] if images else None
        badges = (
            db.session.query(ProductBadge, Badge)
            .join(Badge, Badge.id == ProductBadge.badge_id)
            .filter(
                ProductBadge.product_id == product.id,
                Badge.is_active.is_(True),
            )
            .order_by(ProductBadge.sort_order, ProductBadge.id)
            .all()
        )
        return {
            "id": product.id,
            "sku": product.sku,
            "name": product.name,
            "slug": product.slug,
            "description": product.description,
            "price": str(product.base_price),
            "compare_at_price": str(product.compare_at_price) if product.compare_at_price is not None else None,
            "brand": {
                "id": brand.id,
                "name": brand.name,
            } if brand else None,
            "image_url": primary_image,
            "images": images,
            "badges": [
                {
                    "id": badge.id,
                    "code": badge.code,
                    "name": badge.name,
                    "custom_text": product_badge.custom_text,
                    "sort_order": int(product_badge.sort_order or 0),
                    "settings": dict(product_badge.settings_json or {}),
                    "bg_color": badge.bg_color,
                    "text_color": badge.text_color,
                    "style": badge.style,
                    "storefront_tab": badge.storefront_tab,
                }
                for product_badge, badge in badges
            ],
        }

    @staticmethod
    def trend_display_settings():
        defaults = {
            "hero_height": 238,
            "hero_card_top": 44,
            "hero_card_width": 282,
            "hero_card_height": 168,
            "hero_card_radius": 9,
            "hero_card_border_width": 1,
            "hero_card_border_color": "#ffffff",
            "hero_background_overlay_color": "#000000",
            "hero_background_overlay_opacity": 0.47,
            "hero_card_overlay_color": "#000000",
            "hero_card_overlay_opacity": 0.48,
            "content_padding": 10,
            "show_title": True,
            "show_description": True,
            "title_align": "center",
            "description_align": "center",
            "title_show_arrow": True,
            "title_arrow": ">",
            "title_arrow_color": "#ffffff",
            "show_title_hash": True,
            "title_hash_text": "#",
            "title_hash_color": "#ffffff",
            "title_arrow_font_size": 16,
            "title_arrow_gap": 4,
            "title_color": "#ffffff",
            "title_font_size": 18,
            "title_font_weight": 900,
            "title_spacing": 5,
            "promo_color": "#ffffff",
            "promo_font_size": 10.5,
            "promo_font_weight": 700,
            "promo_max_lines": 2,
            "product_width": 0,
            "product_height": 0,
            "product_top_spacing": 72,
            "product_gap": 4,
            "product_radius": 7,
            "product_info_height": 27,
            "show_product_name": True,
            "show_product_price": True,
            "product_name_font_size": 8.5,
            "product_price_font_size": 9.5,
            "product_name_font_weight": 800,
            "product_price_font_weight": 900,
            "product_name_max_lines": 2,
            "product_name_align": "right",
            "product_price_align": "right",
            "product_name_color": "#000000",
            "product_price_color": "#000000",
            "product_text_color": "#000000",
            "product_info_background_color": "#ffffff",
            "product_image_fit": "cover",
            "hero_product_radius": 7,
            "hero_product_info_height": 27,
            "hero_show_product_name": True,
            "hero_show_product_price": True,
            "hero_product_name_font_size": 8.5,
            "hero_product_price_font_size": 9.5,
            "hero_product_name_font_weight": 800,
            "hero_product_price_font_weight": 900,
            "hero_product_name_max_lines": 2,
            "hero_product_name_align": "right",
            "hero_product_price_align": "right",
            "hero_product_name_color": "#000000",
            "hero_product_price_color": "#000000",
            "hero_product_text_color": "#000000",
            "hero_product_info_background_color": "#ffffff",
            "hero_product_image_fit": "cover",
            "badge_text": "",
            "badge_background_color": "#111827",
            "badge_text_color": "#ffffff",
            "badge_font_size": 9.5,
            "badge_radius": 4,
            "badge_position": "top_right",
            "counter_color": "#ffffff",
            "counter_font_size": 12,
            "counter_bottom": 8,
            "counter_align": "center",
            "show_counter": True,
            "timer_background_color": "#111827",
            "timer_text_color": "#ffffff",
            "timer_font_size": 9,
            "timer_radius": 4,
            "timer_position": "top_left",
            "show_timer": True,
            "top_icon_color": "#ffffff",
            "logo_text": "Trends",
            "logo_color": "#ffffff",
            "logo_font_size": 26,
            "logo_letter_spacing": -1.4,
            "tabs_active_color": "#000000",
            "tabs_inactive_color": "#777777",
            "tabs_indicator_color": "#000000",
            "tabs_indicator_width": 86,
            "tabs_font_size": 17,
            "hashtag_text_color": "#4c4c4c",
            "hashtag_active_text_color": "#8355e6",
            "hashtag_background_color": "#f3f4f7",
            "hashtag_active_background_color": "#f0e6ff",
            "hashtag_font_size": 11,
            "hashtag_height": 31,
            "hashtag_horizontal_padding": 13,
            "hashtag_radius": 0,
            "pull_enabled": True,
            "pull_text": "اسحب للتحديث",
            "pull_release_text": "حرر للتحديث",
            "pull_background_color": "#ffffff",
            "pull_indicator_color": "#000000",
            "pull_text_color": "#555555",
            "pull_font_size": 11,
            "pull_height": 48,
            "pull_distance": 70,
            "page_background_color": "#ffffff",
            "content_top_radius": 14,
            "header_collapse_enabled": True,
            "header_collapse_offset": 46,
            "compact_header_height": 58,
            "search_width_ratio": 0.72,
            "search_height": 42,
            "search_radius": 13,
            "search_horizontal_padding": 10,
            "search_icon_size": 22,
            "search_font_size": 13,
            "search_hint": "فساتين",
            "search_background_color": "#ffffff",
            "search_text_color": "#222222",
            "search_icon_color": "#111111",
            "search_divider_color": "#dddddd",
            "search_divider_width": 1,
            "trend_store_card_height": 330,
            "trend_store_image_height": 252,
            "trend_store_content_height": 78,
            "trend_store_radius": 10,
            "trend_store_content_background": "#ffffff",
            "trend_store_content_padding": 9,
            "trend_store_show_title": True,
            "trend_store_show_description": True,
            "trend_store_title_offset": 0,
            "trend_store_title_align": "center",
            "trend_store_title_show_arrow": True,
            "trend_store_title_arrow": ">",
            "trend_store_title_arrow_color": "#111111",
            "trend_store_title_arrow_font_size": 14,
            "trend_store_title_arrow_gap": 4,
            "trend_store_title_spacing": 3,
            "trend_store_title_font_size": 14,
            "trend_store_title_font_weight": 800,
            "trend_store_title_color": "#111111",
            "trend_store_promo_offset": 2,
            "trend_store_promo_align": "center",
            "trend_store_promo_font_size": 10,
            "trend_store_promo_font_weight": 500,
            "trend_store_promo_color": "#777777",
            "picks_card_extent": 350,
            "picks_image_height": 258,
            "picks_content_height": 92,
            "picks_title_font_size": 11,
            "picks_section_background_color": "#f3f3f3",
        }
        row = AppSetting.query.filter_by(
            group_code="trends",
            key="display_settings",
        ).first()
        custom = {}
        if row and row.value:
            try:
                import json
                decoded = json.loads(row.value)
                if isinstance(decoded, dict):
                    custom = decoded
            except (TypeError, ValueError):
                custom = {}
        merged = {**defaults, **custom}
        legacy_hero_keys = {
            "hero_product_radius": "product_radius",
            "hero_product_info_height": "product_info_height",
            "hero_show_product_name": "show_product_name",
            "hero_show_product_price": "show_product_price",
            "hero_product_name_font_size": "product_name_font_size",
            "hero_product_price_font_size": "product_price_font_size",
            "hero_product_name_font_weight": "product_name_font_weight",
            "hero_product_price_font_weight": "product_price_font_weight",
            "hero_product_name_max_lines": "product_name_max_lines",
            "hero_product_name_align": "product_name_align",
            "hero_product_price_align": "product_price_align",
            "hero_product_name_color": "product_name_color",
            "hero_product_price_color": "product_price_color",
            "hero_product_text_color": "product_text_color",
            "hero_product_info_background_color": "product_info_background_color",
            "hero_product_image_fit": "product_image_fit",
        }
        for new_name, old_name in legacy_hero_keys.items():
            if new_name not in custom and old_name in custom:
                merged[new_name] = custom[old_name]

        def number(name, low, high, integer=False):
            value = merged.get(name, defaults[name])
            try:
                value = float(value)
            except (TypeError, ValueError):
                value = float(defaults[name])
            value = max(low, min(high, value))
            return int(round(value)) if integer else value

        def flag(name, fallback=True):
            value = merged.get(name, fallback)
            if isinstance(value, str):
                normalized = value.strip().lower()
                if normalized in {"false", "0", "no", "off", "disabled"}:
                    return False
                if normalized in {"true", "1", "yes", "on", "enabled"}:
                    return True
            return bool(value)

        numeric_ranges = (
            ("hero_height", 180, 520, True),
            ("hero_card_top", 35, 180, True),
            ("hero_card_width", 220, 520, True),
            ("hero_card_height", 120, 360, True),
            ("hero_card_radius", 0, 40, True),
            ("hero_card_border_width", 0, 5, False),
            ("content_padding", 0, 30, True),
            ("title_font_size", 10, 34, False),
            ("title_font_weight", 400, 900, True),
            ("title_spacing", 0, 20, True),
            ("title_arrow_font_size", 9, 28, False),
            ("title_arrow_gap", 0, 20, True),
            ("promo_font_size", 7, 18, False),
            ("promo_font_weight", 400, 900, True),
            ("promo_max_lines", 1, 3, True),
            ("product_width", 0, 180, False),
            ("product_height", 0, 320, True),
            ("product_top_spacing", 8, 120, True),
            ("product_gap", 0, 20, True),
            ("product_radius", 0, 20, True),
            ("hero_product_radius", 0, 20, True),
            ("hero_product_info_height", 16, 55, True),
            ("hero_product_name_font_size", 6, 14, False),
            ("hero_product_price_font_size", 7, 15, False),
            ("hero_product_name_font_weight", 400, 900, True),
            ("hero_product_price_font_weight", 400, 900, True),
            ("hero_product_name_max_lines", 1, 3, True),
            ("product_info_height", 16, 55, True),
            ("product_name_font_size", 6, 14, False),
            ("product_price_font_size", 7, 15, False),
            ("product_name_font_weight", 400, 900, True),
            ("product_price_font_weight", 400, 900, True),
            ("product_name_max_lines", 1, 3, True),
            ("badge_font_size", 7, 16, False),
            ("badge_radius", 0, 16, True),
            ("counter_font_size", 7, 18, True),
            ("counter_bottom", 0, 30, True),
            ("hashtag_height", 24, 48, True),
            ("hashtag_horizontal_padding", 4, 28, True),
            ("timer_font_size", 7, 16, False),
            ("timer_radius", 0, 16, True),
            ("logo_font_size", 14, 40, True),
            ("logo_letter_spacing", -4, 2, False),
            ("tabs_indicator_width", 40, 180, True),
            ("tabs_font_size", 10, 28, False),
            ("hashtag_font_size", 8, 18, False),
            ("hashtag_radius", 0, 20, True),
            ("pull_font_size", 8, 20, False),
            ("pull_height", 28, 100, True),
            ("pull_distance", 30, 130, True),
            ("content_top_radius", 0, 40, True),
            ("header_collapse_offset", 0, 140, False),
            ("compact_header_height", 44, 96, True),
            ("search_width_ratio", 0.45, 0.9, False),
            ("search_height", 32, 58, True),
            ("search_radius", 0, 30, True),
            ("search_horizontal_padding", 4, 24, True),
            ("search_icon_size", 14, 30, True),
            ("search_font_size", 9, 20, False),
            ("search_divider_width", 0, 4, False),
            ("trend_store_card_height", 220, 520, True),
            ("trend_store_image_height", 140, 430, True),
            ("trend_store_content_height", 50, 140, True),
            ("trend_store_radius", 0, 30, True),
            ("trend_store_content_padding", 4, 24, True),
            ("trend_store_title_offset", -30, 30, True),
            ("trend_store_title_arrow_font_size", 9, 28, False),
            ("trend_store_title_arrow_gap", 0, 20, True),
            ("trend_store_title_font_size", 9, 28, False),
            ("trend_store_title_font_weight", 400, 900, True),
            ("trend_store_promo_offset", -30, 30, True),
            ("trend_store_promo_font_size", 8, 20, False),
            ("trend_store_promo_font_weight", 400, 900, True),
            ("picks_card_extent", 280, 520, True),
            ("picks_image_height", 190, 390, True),
            ("picks_content_height", 60, 150, True),
            ("picks_title_font_size", 8, 18, False),
        )
        for name, low, high, integer in numeric_ranges:
            merged[name] = number(name, low, high, integer)

        for name in ("hero_background_overlay_opacity", "hero_card_overlay_opacity"):
            merged[name] = number(name, 0, 1)

        merged["show_counter"] = flag("show_counter", True)
        merged["show_timer"] = flag("show_timer", True)
        merged["pull_enabled"] = flag("pull_enabled", True)
        merged["header_collapse_enabled"] = flag("header_collapse_enabled", True)
        merged["hero_product_image_fit"] = (
            merged.get("hero_product_image_fit")
            if merged.get("hero_product_image_fit") in {"cover", "contain", "fill"}
            else "cover"
        )
        merged["product_image_fit"] = (
            merged.get("product_image_fit")
            if merged.get("product_image_fit") in {"cover", "contain", "fill"}
            else "cover"
        )
        for name in (
            "product_name_align",
            "product_price_align",
            "hero_product_name_align",
            "hero_product_price_align",
            "title_align",
            "description_align",
            "trend_store_title_align",
            "trend_store_promo_align",
        ):
            merged[name] = (
                merged.get(name)
                if merged.get(name) in {"left", "center", "right"}
                else "center"
            )
        merged["title_show_arrow"] = bool(merged.get("title_show_arrow", True))
        merged["show_title_hash"] = flag("show_title_hash", True)
        title_hash_text = str(merged.get("title_hash_text", "#") or "#").strip()[:3]
        merged["title_hash_text"] = title_hash_text or "#"
        merged["trend_store_title_show_arrow"] = flag("trend_store_title_show_arrow", True)
        merged["show_title"] = flag("show_title", True)
        merged["show_description"] = flag("show_description", True)
        merged["show_product_name"] = flag("show_product_name", True)
        merged["show_product_price"] = flag("show_product_price", True)
        merged["hero_show_product_name"] = flag("hero_show_product_name", True)
        merged["hero_show_product_price"] = flag("hero_show_product_price", True)
        merged["product_name_max_lines"] = number("product_name_max_lines", 1, 3, True)
        merged["hero_product_name_max_lines"] = number("hero_product_name_max_lines", 1, 3, True)
        merged["trend_store_show_title"] = flag("trend_store_show_title", True)
        merged["trend_store_show_description"] = flag("trend_store_show_description", True)
        merged["title_arrow"] = merged.get("title_arrow") if merged.get("title_arrow") in {">", "<"} else ">"
        merged["trend_store_title_arrow"] = merged.get("trend_store_title_arrow") if merged.get("trend_store_title_arrow") in {">", "<"} else ">"
        merged["title_arrow_gap"] = number("title_arrow_gap", 0, 20, True)
        merged["trend_store_title_arrow_gap"] = number("trend_store_title_arrow_gap", 0, 20, True)
        merged["timer_position"] = (
            merged.get("timer_position")
            if merged.get("timer_position") in {"top_left", "top_right"}
            else "top_left"
        )
        merged["badge_position"] = (
            merged.get("badge_position")
            if merged.get("badge_position") in {"top_left", "top_right"}
            else "top_right"
        )
        return merged

    @staticmethod
    def _trend_ui_settings(trend):
        return CatalogService.trend_display_settings()

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
            product_payload = CatalogService._serialize_trend_product(product)
            selected_asset = (
                db.session.get(MediaAsset, assignment.image_asset_id)
                if assignment.image_asset_id else None
            )
            if selected_asset is not None:
                product_payload["image_url"] = selected_asset.url
            products.append({
                "slot": assignment.slot,
                "image_asset_id": assignment.image_asset_id,
                "settings": assignment.settings_json if isinstance(assignment.settings_json, dict) else {},
                "product": product_payload,
            })

        started_at = trend.timer_started_at
        if started_at is not None and started_at.tzinfo is None:
            started_at = started_at.replace(tzinfo=timezone.utc)
        timer_seconds = CatalogService._trend_timer_seconds(trend)
        ends_at = (
            (started_at + timedelta(seconds=timer_seconds)).isoformat()
            if started_at is not None and timer_seconds
            else None
        )
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
                "started_at": started_at.isoformat() if started_at else None,
                "ends_at": ends_at,
            },
            "overlay": {
                "text": trend.overlay_text,
                "text_color": trend.overlay_text_color,
                "background_color": trend.overlay_background_color,
            },
            "ui": CatalogService._trend_ui_settings(trend),
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
    def list_public_trend_hashtags(limit=50):
        rows = (
            Hashtag.query
            .filter(Hashtag.is_active.is_(True))
            .order_by(Hashtag.sort_order, Hashtag.id)
            .limit(min(max(int(limit), 1), 500))
            .all()
        )
        return [
            {
                "id": row.id,
                "name": row.name,
                "slug": row.slug,
                "display_name": row.display_name or f"#{row.name}",
            }
            for row in rows
        ]

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
