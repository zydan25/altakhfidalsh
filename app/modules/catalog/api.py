from decimal import Decimal, InvalidOperation

from flask import request

from . import api_bp
from ...security import admin_api_required
from .services import CatalogService, MediaService
from ...extensions import db
from ...models import (
    Category,
    CategoryFilterDefinition,
    CategoryFilterValue,
    MediaAsset,
    Badge,
    Color,
    Trend,
    TrendProduct,
    Product,
    ProductBadge,
    ProductCategory,
    ProductDisplaySettings,
    ProductFilterValue,
    ProductHashtag,
    ProductMedia,
    ProductSideCategoryCircle,
    ProductVariant,
    ProductOption,
    ProductOptionValue,
    ProductColorReference,
    ProductSizeReference,
    Size,
    Brand,
    Hashtag,
    Review,
    Order,
    OrderItem,
    SideCategory,
    SideCategoryCircle,
)


# Negative IDs identify server-side standard dimensions. They never collide
# with CategoryFilterValue primary keys.
_COLOR_FILTER_OFFSET = 1_000_000
_SIZE_FILTER_OFFSET = 2_000_000
_BRAND_FILTER_OFFSET = 3_000_000
_CATEGORY_FILTER_OFFSET = 4_000_000

@api_bp.get("/categories")
def categories():
    return {"items": CatalogService.list_categories()}


@api_bp.post("/categories")
@admin_api_required("category.manage")
def create_category():
    payload = request.get_json(silent=True) or {}
    try:
        category = CatalogService.create_category(payload)
    except ValueError as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400
    return {"item": category}, 201


@api_bp.patch("/categories/<int:category_id>")
@admin_api_required("category.manage")
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
@admin_api_required("category.manage")
def delete_category(category_id):
    try:
        CatalogService.delete_category(category_id)
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400
    return {"ok": True}


@api_bp.get("/side-circle-display")
def side_circle_display():
    return {"item": CatalogService.get_side_circle_display()}


@api_bp.get("/side-circle-groups")
def side_circle_groups():
    root_id = request.args.get("root_category_id", type=int)
    return {"items": CatalogService.list_side_circle_groups(root_category_id=root_id, public_scope=True)}


@api_bp.get("/side-categories")
def side_categories():
    root_id = request.args.get("root_category_id", type=int)
    return {"items": CatalogService.list_side_categories(root_category_id=root_id)}


@api_bp.post("/side-categories")
@admin_api_required("side_category.manage")
def create_side_category():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_side_category(payload)}, 201
    except ValueError as exc:
        return {"error": "invalid_side_category", "detail": str(exc)}, 400


@api_bp.patch("/side-categories/<int:side_category_id>")
@admin_api_required("side_category.manage")
def update_side_category(side_category_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_side_category(side_category_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_side_category", "detail": str(exc)}, 400


@api_bp.delete("/side-categories/<int:side_category_id>")
@admin_api_required("side_category.manage")
def delete_side_category(side_category_id):
    try:
        CatalogService.archive_side_category(side_category_id)
        return {"ok": True}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.post("/side-categories/<int:side_category_id>/circles")
@admin_api_required("side_category.manage")
def create_side_category_circle(side_category_id):
    try:
        item = CatalogService.create_side_category_circle(
            side_category_id,
            request.form,
            request.files.getlist("files"),
        )
        return {"item": item}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_side_category_circle", "detail": str(exc)}, 400


@api_bp.patch("/side-category-circles/<int:circle_id>")
@admin_api_required("side_category.manage")
def update_side_category_circle(circle_id):
    payload = request.form if request.form else (request.get_json(silent=True) or {})
    try:
        item = CatalogService.update_side_category_circle(
            circle_id,
            payload,
            request.files.getlist("files"),
        )
        return {"item": item}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_side_category_circle", "detail": str(exc)}, 400


@api_bp.delete("/side-category-circles/<int:circle_id>")
@admin_api_required("side_category.manage")
def delete_side_category_circle(circle_id):
    try:
        CatalogService.archive_side_category_circle(circle_id)
        return {"ok": True}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.get("/side-category-circles/<int:circle_id>/products")
def side_category_circle_products(circle_id):
    exists = db.session.get(SideCategoryCircle, circle_id)
    if exists is None or not exists.is_active:
        return {"error": "not_found", "detail": "side category circle not found"}, 404
    rows = (
        db.session.query(Product)
        .join(ProductSideCategoryCircle, ProductSideCategoryCircle.product_id == Product.id)
        .filter(
            ProductSideCategoryCircle.circle_id == circle_id,
            Product.is_active.is_(True),
            Product.status == "published",
        )
        .order_by(Product.id.desc())
        .limit(min(max(request.args.get("limit", 50, type=int), 1), 100))
        .all()
    )
    return {"items": [CatalogService._serialize_trend_product(row) for row in rows]}


@api_bp.get("/reference/side-category-circles")
@admin_api_required("side_category.view")
def side_category_circle_references():
    side_id = request.args.get("side_category_id", type=int)
    query = SideCategoryCircle.query
    if side_id:
        query = query.filter_by(side_category_id=side_id)
    rows = query.filter(SideCategoryCircle.is_active.is_(True)).order_by(
        SideCategoryCircle.sort_order, SideCategoryCircle.name
    ).all()
    return {
        "items": [
            CatalogService._serialize_side_category_circle(row, include_products=True)
            for row in rows
        ]
    }


@api_bp.get("/products")
def products():
    return {"items": CatalogService.list_products()}


@api_bp.get("/products/feed")
def public_product_feed():
    """Mobile storefront feed with dynamic filters, sorting, price range and currency."""
    from sqlalchemy import func, or_
    from ..customer.security import current_customer
    from ...services.pricing import price_for_customer

    query = Product.query.filter(
        Product.is_active.is_(True),
        Product.status == "published",
    )

    def _parse_id_list(name):
        values = []
        raw_values = (request.args.get(name) or "").split(",")
        for raw in raw_values:
            raw = raw.strip()
            if not raw:
                continue
            try:
                value = int(raw)
            except (TypeError, ValueError):
                continue
            if value > 0 and value not in values:
                values.append(value)
        return values

    category_id = request.args.get("category_id", type=int)
    category_ids = _parse_id_list("category_ids")
    if category_id and category_id not in category_ids:
        category_ids.insert(0, category_id)

    circle_id = request.args.get("circle_id", type=int)
    hashtag_id = request.args.get("hashtag_id", type=int)
    hashtag_ids = _parse_id_list("hashtag_ids")
    if hashtag_id and hashtag_id not in hashtag_ids:
        hashtag_ids.insert(0, hashtag_id)

    side_category_id = request.args.get("side_category_id", type=int)
    search = (request.args.get("q") or "").strip()
    currency_id = request.args.get("currency_id", type=int)
    sort = (request.args.get("sort") or "recommended").strip().lower()
    discovery_tab = (request.args.get("discovery_tab") or "").strip().lower()
    min_price_raw = (request.args.get("min_price") or "").strip()
    max_price_raw = (request.args.get("max_price") or "").strip()

    category_scope_ids = []
    for requested_category_id in category_ids:
        category_scope_ids.extend(
            CatalogService.category_descendant_ids(requested_category_id)
        )
    category_scope_ids = sorted(set(category_scope_ids))

    if category_scope_ids:
        query = query.join(
            ProductCategory,
            ProductCategory.product_id == Product.id,
        ).filter(ProductCategory.category_id.in_(category_scope_ids))

    if side_category_id:
        side_category = db.session.get(SideCategory, side_category_id)
        if side_category is None or not side_category.is_active:
            return {"items": [], "count": 0}

        side_circle_ids = [
            row.id
            for row in SideCategoryCircle.query.filter(
                SideCategoryCircle.side_category_id == side_category.id,
                SideCategoryCircle.is_active.is_(True),
            ).all()
        ]

        if circle_id is not None:
            # A circle result is narrower than its parent side category.
            # Use the same relationship JOIN for both constraints instead of
            # joining ProductSideCategoryCircle twice.
            side_circle_ids = [circle_id] if circle_id in side_circle_ids else []

        if not side_circle_ids:
            query = query.filter(Product.id == -1)
        else:
            query = query.join(
                ProductSideCategoryCircle,
                ProductSideCategoryCircle.product_id == Product.id,
            ).filter(ProductSideCategoryCircle.circle_id.in_(side_circle_ids))

    elif circle_id:
        query = query.join(
            ProductSideCategoryCircle,
            ProductSideCategoryCircle.product_id == Product.id,
        ).filter(ProductSideCategoryCircle.circle_id == circle_id)

    if hashtag_ids:
        query = query.join(
            ProductHashtag,
            ProductHashtag.product_id == Product.id,
        ).filter(ProductHashtag.hashtag_id.in_(hashtag_ids))

    if search:
        needle = "%" + search + "%"
        query = query.filter(or_(
            Product.name.ilike(needle),
            Product.sku.ilike(needle),
            Product.slug.ilike(needle),
        ))

    if discovery_tab in {"new", "offers"}:
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        query = (
            query
            .join(ProductBadge, ProductBadge.product_id == Product.id)
            .join(Badge, Badge.id == ProductBadge.badge_id)
            .filter(
                Badge.is_active.is_(True),
                Badge.storefront_tab == discovery_tab,
                or_(ProductBadge.starts_at.is_(None), ProductBadge.starts_at <= now),
                or_(ProductBadge.ends_at.is_(None), ProductBadge.ends_at > now),
            )
            .distinct()
        )

    elif discovery_tab == "trends":
        # The Trends screen's "لك" tab must contain only products that are
        # explicitly assigned to an active, non-expired trend. Do not fall
        # back to the general popular-products feed.
        active_trend_ids = [
            trend.id
            for trend in Trend.query.filter(
                Trend.is_active.is_(True),
                Trend.status == "active",
            ).all()
            if not CatalogService.is_trend_timer_expired(trend)
        ]
        if not active_trend_ids:
            query = query.filter(Product.id == -1)
        else:
            trend_products = (
                db.session.query(TrendProduct.product_id)
                .filter(TrendProduct.trend_id.in_(active_trend_ids))
                .distinct()
                .subquery()
            )
            query = query.filter(
                Product.id.in_(db.session.query(trend_products.c.product_id))
            )

    # OR within one filter group, AND between different filter groups.
    selected_filter_ids = []
    raw_filter_ids = (request.args.get("filter_value_ids") or "").split(",")
    for raw in raw_filter_ids:
        raw = raw.strip()
        if not raw:
            continue
        try:
            value_id = int(raw)
        except ValueError:
            continue
        if value_id != 0 and value_id not in selected_filter_ids:
            selected_filter_ids.append(value_id)

    # Positive IDs are CategoryFilterValue records.
    custom_filter_ids = [value_id for value_id in selected_filter_ids if value_id > 0]

    if custom_filter_ids:
        valid_values = (
            db.session.query(CategoryFilterValue, CategoryFilterDefinition)
            .join(
                CategoryFilterDefinition,
                CategoryFilterDefinition.id == CategoryFilterValue.filter_id,
            )
            .filter(
                CategoryFilterValue.id.in_(custom_filter_ids),
                CategoryFilterValue.is_active.is_(True),
            )
        )
        if category_scope_ids:
            valid_values = valid_values.filter(
                CategoryFilterDefinition.category_id.in_(category_scope_ids),
                CategoryFilterDefinition.is_active.is_(True),
            )
        elif side_category_id:
            side_category = db.session.get(SideCategory, side_category_id)
            if side_category is not None and side_category.is_active:
                valid_values = valid_values.filter(
                    CategoryFilterDefinition.category_id.in_(
                        CatalogService.category_descendant_ids(
                            side_category.root_category_id
                        )
                    ),
                    CategoryFilterDefinition.is_active.is_(True),
                )
        rows = valid_values.all()

        grouped = {}
        for value, definition in rows:
            group_key = (
                (definition.name or "").strip().casefold(),
                (definition.filter_type or "").strip().casefold(),
            )
            grouped.setdefault(group_key, []).append(int(value.id))

        for value_ids in grouped.values():
            matching_products = (
                db.session.query(ProductFilterValue.product_id)
                .filter(ProductFilterValue.filter_value_id.in_(value_ids))
                .distinct()
                .subquery()
            )
            query = query.filter(
                Product.id.in_(db.session.query(matching_products.c.product_id))
            )

    # Negative IDs are server-side standard dimensions exposed by
    # /products/filters: color, size and brand.
    selected_color_ids = {
        -value_id - _COLOR_FILTER_OFFSET
        for value_id in selected_filter_ids
        if value_id < 0 and (-value_id) > _COLOR_FILTER_OFFSET
        and (-value_id) < _SIZE_FILTER_OFFSET
    }
    selected_size_ids = {
        -value_id - _SIZE_FILTER_OFFSET
        for value_id in selected_filter_ids
        if value_id < 0 and (-value_id) > _SIZE_FILTER_OFFSET
        and (-value_id) < _BRAND_FILTER_OFFSET
    }
    selected_brand_ids = {
        -value_id - _BRAND_FILTER_OFFSET
        for value_id in selected_filter_ids
        if value_id < 0 and (-value_id) > _BRAND_FILTER_OFFSET
        and (-value_id) < _CATEGORY_FILTER_OFFSET
    }
    selected_category_filter_ids = {
        -value_id - _CATEGORY_FILTER_OFFSET
        for value_id in selected_filter_ids
        if value_id < 0 and (-value_id) > _CATEGORY_FILTER_OFFSET
    }

    if selected_color_ids:
        variant_color_products = (
            db.session.query(ProductVariant.product_id)
            .filter(
                ProductVariant.color_id.in_(sorted(selected_color_ids)),
                ProductVariant.is_active.is_(True),
            )
            .distinct()
        )
        reference_color_products = (
            db.session.query(ProductColorReference.product_id)
            .filter(ProductColorReference.color_id.in_(sorted(selected_color_ids)))
            .distinct()
        )
        media_color_products = (
            db.session.query(ProductMedia.product_id)
            .filter(ProductMedia.color_id.in_(sorted(selected_color_ids)))
            .distinct()
        )
        query = query.filter(or_(
            Product.id.in_(variant_color_products),
            Product.id.in_(reference_color_products),
            Product.id.in_(media_color_products),
        ))

    if selected_size_ids:
        variant_size_products = (
            db.session.query(ProductVariant.product_id)
            .filter(
                ProductVariant.size_id.in_(sorted(selected_size_ids)),
                ProductVariant.is_active.is_(True),
            )
            .distinct()
        )
        reference_size_products = (
            db.session.query(ProductSizeReference.product_id)
            .filter(ProductSizeReference.size_id.in_(sorted(selected_size_ids)))
            .distinct()
        )
        option_size_products = (
            db.session.query(ProductOption.product_id)
            .join(ProductOptionValue, ProductOptionValue.option_id == ProductOption.id)
            .filter(ProductOptionValue.size_id.in_(sorted(selected_size_ids)))
            .distinct()
        )
        query = query.filter(or_(
            Product.id.in_(variant_size_products),
            Product.id.in_(reference_size_products),
            Product.id.in_(option_size_products),
        ))

    if selected_brand_ids:
        query = query.filter(Product.brand_id.in_(sorted(selected_brand_ids)))

    if selected_category_filter_ids:
        query = query.join(
            ProductCategory,
            ProductCategory.product_id == Product.id,
        ).filter(
            ProductCategory.category_id.in_(sorted(selected_category_filter_ids))
        )

    # Relation joins above can duplicate a product. Collapse them before the
    # predictable candidate limit is applied.
    query = query.distinct()

    # Keep the database candidate set predictable; final pricing/sorting is done after
    # customer/city/currency pricing has been resolved.
    rows = query.order_by(Product.id.desc()).limit(100).all()

    media_by_product = {}
    product_ids = [row.id for row in rows]
    if product_ids:
        media_rows = (
            db.session.query(
                ProductMedia.product_id,
                ProductMedia.color_id,
                MediaAsset.url,
                MediaAsset.width,
                MediaAsset.height,
            )
            .join(MediaAsset, MediaAsset.id == ProductMedia.asset_id)
            .filter(ProductMedia.product_id.in_(product_ids))
            .order_by(ProductMedia.product_id, ProductMedia.sort_order, ProductMedia.id)
            .all()
        )
        for product_id, color_id, media_url, width, height in media_rows:
            media_by_product.setdefault(product_id, []).append({
                "url": media_url,
                "width": width,
                "height": height,
                "color_id": color_id,
            })

    color_ids = {
        int(media["color_id"])
        for rows_for_product in media_by_product.values()
        for media in rows_for_product
        if media.get("color_id")
    }
    colors_by_id = {}
    if color_ids:
        color_rows = (
            db.session.query(Color, MediaAsset)
            .outerjoin(MediaAsset, MediaAsset.id == Color.swatch_asset_id)
            .filter(Color.id.in_(color_ids))
            .all()
        )
        colors_by_id = {
            color.id: {
                "id": color.id,
                "name": color.name,
                "hex_code": color.hex_code,
                "swatch_url": swatch.url if swatch else None,
            }
            for color, swatch in color_rows
        }

    trend_product_ids = set()
    trend_card_by_product = {}
    if product_ids:
        trend_rows = (
            db.session.query(TrendProduct, Trend, Hashtag)
            .join(Trend, Trend.id == TrendProduct.trend_id)
            .join(Hashtag, Hashtag.id == Trend.hashtag_id)
            .filter(
                TrendProduct.product_id.in_(product_ids),
                Trend.is_active.is_(True),
                Trend.status == "active",
                Hashtag.is_active.is_(True),
            )
            .order_by(
                TrendProduct.product_id,
                Trend.sort_order,
                Trend.id.desc(),
                TrendProduct.slot,
            )
            .all()
        )
        for trend_product, trend, hashtag in trend_rows:
            if CatalogService.is_trend_timer_expired(trend):
                continue
            product_id = int(trend_product.product_id)
            trend_product_ids.add(product_id)
            if product_id in trend_card_by_product:
                continue
            assignment_settings = (
                trend_product.settings_json
                if isinstance(trend_product.settings_json, dict)
                else {}
            )
            trend_card_by_product[product_id] = {
                "id": trend.id,
                "hashtag": {
                    "id": hashtag.id,
                    "name": hashtag.name,
                    "slug": hashtag.slug,
                    "display_name": hashtag.display_name or f"#{hashtag.name}",
                },
                "settings": assignment_settings,
            }

    hashtags_by_product = {}
    if product_ids:
        hashtag_rows = (
            db.session.query(ProductHashtag.product_id, Hashtag)
            .join(Hashtag, Hashtag.id == ProductHashtag.hashtag_id)
            .filter(
                ProductHashtag.product_id.in_(product_ids),
                Hashtag.is_active.is_(True),
            )
            .order_by(
                ProductHashtag.product_id,
                Hashtag.sort_order,
                Hashtag.id,
            )
            .all()
        )
        for product_id, hashtag in hashtag_rows:
            bucket = hashtags_by_product.setdefault(int(product_id), [])
            bucket.append({
                "id": hashtag.id,
                "name": hashtag.name,
                "slug": hashtag.slug,
                "display_name": hashtag.display_name or f"#{hashtag.name}",
            })

    # Product cards can expose one compact size/age label without loading the
    # full product-detail payload. Prefer an Age option, then Size option,
    # then the first active variant's catalog size as a safe fallback.
    option_meta_by_product = {}
    if product_ids:
        option_rows = (
            db.session.query(
                ProductOption.product_id,
                ProductOption.name,
                ProductOption.sort_order,
                ProductOptionValue.label,
                ProductOptionValue.sort_order,
            )
            .join(
                ProductOptionValue,
                ProductOptionValue.option_id == ProductOption.id,
            )
            .filter(ProductOption.product_id.in_(product_ids))
            .order_by(
                ProductOption.product_id,
                ProductOption.sort_order,
                ProductOptionValue.sort_order,
                ProductOptionValue.id,
            )
            .all()
        )
        for product_id, option_name, option_sort, label, value_sort in option_rows:
            label_text = (label or "").strip()
            if not label_text:
                continue
            name_text = (option_name or "").strip().casefold()
            kind = None
            if any(token in name_text for token in (
                "age", "year", "years", "عمر", "سن", "سنوات", "الفئة العمرية"
            )):
                kind = "age"
            elif any(token in name_text for token in (
                "size", "sizes", "مقاس", "المقاس", "مقاسات"
            )):
                kind = "size"
            if kind is None:
                continue

            current = option_meta_by_product.get(int(product_id))
            priority = 0 if kind == "age" else 1
            candidate = {
                "label": label_text,
                "kind": kind,
                "_priority": priority,
                "_sort": int(option_sort or 0),
                "_value_sort": int(value_sort or 0),
            }
            if (
                current is None
                or candidate["_priority"] < current["_priority"]
                or (
                    candidate["_priority"] == current["_priority"]
                    and (
                        candidate["_sort"], candidate["_value_sort"]
                    ) < (
                        current["_sort"], current["_value_sort"]
                    )
                )
            ):
                option_meta_by_product[int(product_id)] = candidate

    variant_by_product = {}
    if product_ids:
        variant_rows = (
            db.session.query(ProductVariant.product_id, ProductVariant.id, Size.label)
            .outerjoin(Size, Size.id == ProductVariant.size_id)
            .filter(
                ProductVariant.product_id.in_(product_ids),
                ProductVariant.is_active.is_(True),
            )
            .order_by(ProductVariant.product_id, ProductVariant.id)
            .all()
        )
        for product_id, variant_id, size_label in variant_rows:
            product_key = int(product_id)
            if product_key in variant_by_product:
                continue
            variant_by_product[product_key] = {
                "id": int(variant_id),
                "size_label": (size_label or "").strip() or None,
            }

    for meta in option_meta_by_product.values():
        meta.pop("_priority", None)
        meta.pop("_sort", None)
        meta.pop("_value_sort", None)

    display_by_product = {
        row.product_id: row
        for row in ProductDisplaySettings.query
        .filter(ProductDisplaySettings.product_id.in_(product_ids))
        .all()
    } if product_ids else {}

    category_ids_by_product = {}
    root_category_ids_by_product = {}
    if product_ids:
        category_rows = (
            db.session.query(ProductCategory.product_id, ProductCategory.category_id)
            .filter(ProductCategory.product_id.in_(product_ids))
            .all()
        )
        # Build the hierarchy from the complete category tree. A product
        # can remain attached to a child category even when that child was
        # temporarily archived, so filtering only active categories can lose
        # the root relation needed by the offline storefront.
        category_parent = {
            int(category.id): category.parent_id
            for category in Category.query.all()
        }

        def root_for_category(category_id):
            current = int(category_id)
            seen = set()
            while current not in seen:
                seen.add(current)
                parent = category_parent.get(current)
                if parent is None:
                    return current
                current = int(parent)
            return int(category_id)

        for product_id, category_id in category_rows:
            category_ids_by_product.setdefault(product_id, []).append(category_id)
            root_id = root_for_category(category_id)
            root_category_ids_by_product.setdefault(product_id, set()).add(root_id)

    customer = current_customer()

    # Calculate the two discovery metrics from existing commerce data without adding
    # a new schema: paid/shipped/delivered quantity for popularity and approved active
    # reviews for average rating.
    popularity_by_product = {}
    rating_by_product = {}
    rating_count_by_product = {}
    if product_ids:
        popularity_rows = (
            db.session.query(
                OrderItem.product_id,
                func.coalesce(func.sum(OrderItem.qty), 0),
            )
            .join(Order, Order.id == OrderItem.order_id)
            .filter(
                OrderItem.product_id.in_(product_ids),
                Order.status.in_(("paid", "shipped", "delivered")),
            )
            .group_by(OrderItem.product_id)
            .all()
        )
        popularity_by_product = {
            int(product_id): int(qty or 0)
            for product_id, qty in popularity_rows
        }

        rating_rows = (
            db.session.query(
                Review.product_id,
                func.avg(Review.rating),
                func.count(Review.id),
            )
            .filter(
                Review.product_id.in_(product_ids),
                Review.is_active.is_(True),
                Review.status == "approved",
            )
            .group_by(Review.product_id)
            .all()
        )
        for product_id, average, count in rating_rows:
            rating_by_product[int(product_id)] = float(average or 0)
            rating_count_by_product[int(product_id)] = int(count or 0)

    try:
        min_price = Decimal(min_price_raw) if min_price_raw else None
        max_price = Decimal(max_price_raw) if max_price_raw else None
        min_rating = Decimal(str((request.args.get("min_rating") or "").strip())) if (request.args.get("min_rating") or "").strip() else None
    except (InvalidOperation, ValueError):
        min_price = max_price = min_rating = None

    items = []
    for row in rows:
        item = CatalogService._serialize_trend_product(row)
        row_media = media_by_product.get(row.id, [])
        item["images"] = [x["url"] for x in row_media]
        seen_color_ids = set()
        item_colors = []
        for media in row_media:
            color_id = media.get("color_id")
            if not color_id:
                continue
            color = colors_by_id.get(int(color_id))
            if color is not None and int(color_id) not in seen_color_ids:
                seen_color_ids.add(int(color_id))
                item_colors.append(color)
        item["colors"] = item_colors[:8]
        item["is_trend"] = row.id in trend_product_ids
        if row.id in trend_card_by_product:
            item["trend_card"] = trend_card_by_product[row.id]
        else:
            item["trend_card"] = None
        item["hashtags"] = hashtags_by_product.get(row.id, [])
        card_meta = option_meta_by_product.get(row.id)
        if card_meta is None:
            variant_meta = variant_by_product.get(row.id)
            if variant_meta and variant_meta.get("size_label"):
                card_meta = {
                    "label": variant_meta["size_label"],
                    "kind": "size",
                }
        item["card_meta"] = card_meta
        first_media = row_media[0] if row_media else None
        if first_media and first_media.get("width") and first_media.get("height"):
            item["image_aspect_ratio"] = float(first_media["width"]) / float(first_media["height"])
        display = display_by_product.get(row.id)
        item["card_aspect_ratio"] = display.card_aspect_ratio if display else "3:4"
        item["category_ids"] = category_ids_by_product.get(row.id, [])
        item["root_category_ids"] = sorted(
            root_category_ids_by_product.get(row.id, set())
        )

        from datetime import datetime, timezone
        now_utc = datetime.now(timezone.utc)
        badge_rows = (
            db.session.query(ProductBadge, Badge)
            .join(Badge, Badge.id == ProductBadge.badge_id)
            .filter(
                ProductBadge.product_id == row.id,
                Badge.is_active.is_(True),
                or_(ProductBadge.starts_at.is_(None), ProductBadge.starts_at <= now_utc),
                or_(ProductBadge.ends_at.is_(None), ProductBadge.ends_at > now_utc),
            )
            .order_by(ProductBadge.position, ProductBadge.id)
            .all()
        )
        item["badges"] = [
            {
                "id": badge.id,
                "code": badge.code,
                "name": badge.name,
                "custom_text": product_badge.custom_text,
                "starts_at": product_badge.starts_at.isoformat() if product_badge.starts_at else None,
                "ends_at": product_badge.ends_at.isoformat() if product_badge.ends_at else None,
                "sort_order": int(product_badge.sort_order or 0),
                "settings": dict(product_badge.settings_json or {}),
                "bg_color": badge.bg_color,
                "text_color": badge.text_color,
                "style": badge.style,
                "storefront_tab": badge.storefront_tab,
            }
            for product_badge, badge in badge_rows
        ]

        variant_meta = variant_by_product.get(row.id)
        item["variant_id"] = variant_meta["id"] if variant_meta else None
        item["base_price_sar"] = str(row.base_price)
        item["status"] = row.status

        try:
            context, priced = price_for_customer(
                base_price_sar=row.base_price,
                customer_id=customer.id if customer else None,
                city_id=customer.city_id if customer else None,
                area_id=customer.city_area_id if customer else None,
                currency_id=currency_id,
            )
            item["price"] = str(priced.final)
            item["currency_id"] = context.currency_id
            item["currency_code"] = context.currency_code
            item["fx_rate"] = str(priced.fx_rate)
        except Exception:
            item["price"] = str(row.base_price)
            item["currency_code"] = "SAR"

        current_price = Decimal(str(item["price"]))
        average_rating = rating_by_product.get(row.id, 0.0)
        review_count = rating_count_by_product.get(row.id, 0)
        sold_qty = popularity_by_product.get(row.id, 0)
        if min_price is not None and current_price < min_price:
            continue
        if max_price is not None and current_price > max_price:
            continue
        if min_rating is not None and Decimal(str(average_rating)) < min_rating:
            continue
        item["rating"] = round(average_rating, 2) if review_count else None
        item["review_count"] = review_count
        item["sold_qty"] = sold_qty
        items.append(item)

    if sort == "price_asc":
        items.sort(key=lambda x: Decimal(str(x.get("price", "0"))))
    elif sort == "price_desc":
        items.sort(key=lambda x: Decimal(str(x.get("price", "0"))), reverse=True)
    elif sort in {"newest", "latest"}:
        items.sort(key=lambda x: int(x.get("id", 0)), reverse=True)
    elif sort in {"popular", "most_popular", "best_selling"}:
        items.sort(key=lambda x: (int(x.get("sold_qty", 0)), int(x.get("id", 0))), reverse=True)
    elif sort in {"rating", "rating_desc", "highest_rated"}:
        items.sort(key=lambda x: (float(x.get("rating") or 0), int(x.get("review_count", 0)), int(x.get("id", 0))), reverse=True)
    else:
        # Recommended uses the storefront's default newness order.
        items.sort(key=lambda x: int(x.get("id", 0)), reverse=True)

    limit = min(max(request.args.get("limit", 80, type=int), 1), 100)
    return {"items": items[:limit]}


@api_bp.post("/products/drafts")
@admin_api_required("product.create")
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
@admin_api_required("product.edit")
def update_product(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_product(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_product", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/publish")
@admin_api_required("product.publish")
def publish_product(product_id):
    try:
        return {"item": CatalogService.publish_product(product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "cannot_publish", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/categories")
@admin_api_required("product.edit")
def set_product_categories(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_categories(product_id, payload.get("category_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_categories", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/side-category-circles")
@admin_api_required("product.edit")
def set_product_side_category_circles(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {
            "items": CatalogService.set_product_side_category_circles(
                product_id,
                payload.get("circle_ids", []),
            )
        }
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_side_category_circles", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/options")
@admin_api_required("product.edit")
def add_product_option(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.add_option(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_option", "detail": str(exc)}, 400


@api_bp.patch("/products/<int:product_id>/variants/<int:variant_id>")
@admin_api_required("product.edit")
def update_product_variant(product_id, variant_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_variant(product_id, variant_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_variant", "detail": str(exc)}, 400


@api_bp.delete("/products/<int:product_id>/variants/<int:variant_id>")
@admin_api_required("product.edit")
def archive_product_variant(product_id, variant_id):
    try:
        return {"item": CatalogService.archive_variant(product_id, variant_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.patch("/products/<int:product_id>/options/<int:option_id>")
@admin_api_required("product.edit")
def update_product_option(product_id, option_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.update_option(product_id, option_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_option", "detail": str(exc)}, 400


@api_bp.delete("/products/<int:product_id>/options/<int:option_id>")
@admin_api_required("product.edit")
def delete_product_option(product_id, option_id):
    try:
        return {"item": CatalogService.remove_option(product_id, option_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.post("/products/<int:product_id>/variants")
@admin_api_required("product.edit")
def add_product_variant(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.add_variant(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_variant", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/inventory")
@admin_api_required("inventory.manage")
def set_inventory(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_inventory(product_id, payload)}, 201
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_inventory", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/media")
@admin_api_required("product.edit")
def upload_product_media(product_id):
    try:
        items = MediaService.attach_product_files(product_id, request.files.getlist("files"), color_id=request.form.get("color_id", type=int))
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_media", "detail": str(exc)}, 400
    return {"items": items}, 201



@api_bp.get("/reference/product-side-categories")
def product_side_category_references():
    category_ids = request.args.getlist("category_id", type=int)
    return {
        "items": CatalogService.product_side_category_references(category_ids)
    }


@api_bp.get("/reference/product-config")
def product_config_references():
    product_id = request.args.get("product_id", type=int)
    try:
        return {"item": CatalogService.product_reference_data(product_id=product_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404


@api_bp.post("/reference/categories")
@admin_api_required("category.manage")
def create_category_reference():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_category(payload)}, 201
    except (LookupError, ValueError, TypeError) as exc:
        return {"error": "invalid_category", "detail": str(exc)}, 400


@api_bp.get("/reference/options")
def option_references():
    product_id = request.args.get("product_id", type=int)
    return {"item": CatalogService.option_references(product_id=product_id)}


@api_bp.get("/reference/marketing")
def marketing_references():
    from ...models import Badge, Brand, Hashtag
    return {
        "brands": [
            {"id": x.id, "name": x.name, "slug": x.slug, "logo_asset_id": x.logo_asset_id}
            for x in Brand.query.filter_by(is_active=True).order_by(Brand.name).all()
        ],
        "badges": [
            {
                "id": x.id,
                "name": x.name,
                "code": x.code,
                "bg_color": x.bg_color,
                "text_color": x.text_color,
                "style": x.style,
                "storefront_tab": x.storefront_tab,
            }
            for x in Badge.query.filter_by(is_active=True).order_by(Badge.priority.desc(), Badge.name).all()
        ],
        "hashtags": [
            {"id": x.id, "name": x.name, "slug": x.slug, "display_name": x.display_name}
            for x in Hashtag.query.filter_by(is_active=True).order_by(Hashtag.sort_order, Hashtag.name).all()
        ],
    }


@api_bp.post("/products/<int:product_id>/promotional-strips")
@admin_api_required("product.edit")
def set_product_promotional_strips(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_promotional_strips(product_id, payload.get("strip_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_promotional_strips", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/campaigns")
@admin_api_required("product.edit")
def set_product_campaigns(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_campaigns(product_id, payload.get("campaign_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_campaigns", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/reference-dimensions")
@admin_api_required("product.edit")
def set_product_reference_dimensions(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_product_reference_dimensions(
            product_id,
            payload.get("color_ids", []),
            payload.get("size_ids", []),
        )}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_reference_dimensions", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/badges")
@admin_api_required("product.edit")
def set_product_badges(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        badges = payload.get("badges")
        if badges is None:
            badges = payload.get("badge_ids", [])
        return {"items": CatalogService.set_product_badges(product_id, badges)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_badges", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/hashtags")
@admin_api_required("product.edit")
def set_product_hashtags(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"items": CatalogService.set_product_hashtags(product_id, payload.get("hashtag_ids", []))}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_hashtags", "detail": str(exc)}, 400


@api_bp.get("/inventory-locations")
def inventory_locations():
    return {"items": CatalogService.list_inventory_locations()}


@api_bp.post("/inventory-locations")
@admin_api_required("inventory.manage")
def create_inventory_location():
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_inventory_location(payload)}, 201
    except ValueError as exc:
        return {"error": "invalid_inventory_location", "detail": str(exc)}, 400

@api_bp.post("/products/<int:product_id>/display-settings")
@admin_api_required("product.edit")
def display_settings(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_display_settings(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_display_settings", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/policies")
@admin_api_required("product.edit")
def product_policies(product_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.set_policies(product_id, payload)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "invalid_policy_assignment", "detail": str(exc)}, 400




@api_bp.get("/products/filters")
def product_scope_filters():
    """Build filter options from the actual current storefront product scope.

    Normal catalog categories keep their configured category-filter groups.
    Side-category and circle results use only products assigned to that
    side/circle, so the parent root category is never used as the filter scope.
    """
    def _parse_id_list(name):
        values = []
        for raw in (request.args.get(name) or "").split(","):
            raw = raw.strip()
            if not raw:
                continue
            try:
                value = int(raw)
            except (TypeError, ValueError):
                continue
            if value > 0 and value not in values:
                values.append(value)
        return values

    category_id = request.args.get("category_id", type=int)
    category_ids = _parse_id_list("category_ids")
    if category_id and category_id not in category_ids:
        category_ids.insert(0, category_id)

    circle_id = request.args.get("circle_id", type=int)
    side_category_id = request.args.get("side_category_id", type=int)

    product_query = Product.query.filter(
        Product.is_active.is_(True),
        Product.status == "published",
    )

    category_scope_ids = []
    for requested_category_id in category_ids:
        category_scope_ids.extend(
            CatalogService.category_descendant_ids(requested_category_id)
        )
    category_scope_ids = sorted(set(category_scope_ids))

    if category_scope_ids:
        product_query = product_query.join(
            ProductCategory,
            ProductCategory.product_id == Product.id,
        ).filter(ProductCategory.category_id.in_(category_scope_ids))

    if side_category_id:
        side_category = db.session.get(SideCategory, side_category_id)
        if side_category is None or not side_category.is_active:
            return {"items": []}

        side_circle_ids = [
            int(row.id)
            for row in SideCategoryCircle.query.filter(
                SideCategoryCircle.side_category_id == side_category.id,
                SideCategoryCircle.is_active.is_(True),
            ).all()
        ]
        if circle_id:
            if circle_id not in side_circle_ids:
                return {"items": []}
            side_circle_ids = [circle_id]

        if not side_circle_ids:
            return {"items": []}

        product_query = product_query.join(
            ProductSideCategoryCircle,
            ProductSideCategoryCircle.product_id == Product.id,
        ).filter(ProductSideCategoryCircle.circle_id.in_(side_circle_ids))

    elif circle_id:
        circle = db.session.get(SideCategoryCircle, circle_id)
        if circle is None or not circle.is_active:
            return {"items": []}
        product_query = product_query.join(
            ProductSideCategoryCircle,
            ProductSideCategoryCircle.product_id == Product.id,
        ).filter(ProductSideCategoryCircle.circle_id == circle_id)

    hashtag_id = request.args.get("hashtag_id", type=int)
    hashtag_ids = _parse_id_list("hashtag_ids")
    if hashtag_id and hashtag_id not in hashtag_ids:
        hashtag_ids.insert(0, hashtag_id)
    if hashtag_ids:
        product_query = product_query.join(
            ProductHashtag,
            ProductHashtag.product_id == Product.id,
        ).filter(ProductHashtag.hashtag_id.in_(hashtag_ids))

    product_scope = (
        product_query.with_entities(Product.id)
        .distinct()
        .subquery()
    )

    merged = {}

    def add_group(definition_id, name, filter_type, sort_order, values):
        if not values:
            return
        key = ((name or "").strip().casefold(), (filter_type or "").strip().casefold())
        item = merged.get(key)
        if item is None:
            item = {
                "id": definition_id,
                "name": name,
                "filter_type": filter_type,
                "sort_order": sort_order,
                "values": [],
            }
            merged[key] = item
        seen = {int(value["id"]) for value in item["values"]}
        for value in values:
            if int(value["id"]) not in seen:
                item["values"].append(value)
                seen.add(int(value["id"]))

    # Custom filter definitions are server taxonomy. For a normal category
    # result use its category scope; for a side/circle result derive only the
    # categories actually assigned to products in that side/circle. This keeps
    # all configured values (including currently unused values) while avoiding
    # the unrelated parent root category.
    filter_category_ids = list(category_scope_ids)
    if side_category_id or circle_id:
        scoped_category_rows = (
            db.session.query(ProductCategory.category_id)
            .filter(
                ProductCategory.product_id.in_(
                    db.session.query(product_scope.c.id)
                )
            )
            .distinct()
            .all()
        )
        filter_category_ids = sorted(
            {
                int(category_id)
                for (category_id,) in scoped_category_rows
                if category_id is not None
            }
        )

    custom_filter_query = (
        db.session.query(
            CategoryFilterDefinition.id,
            CategoryFilterDefinition.name,
            CategoryFilterDefinition.filter_type,
            CategoryFilterDefinition.sort_order,
            CategoryFilterValue.id.label("value_id"),
            CategoryFilterValue.label,
            CategoryFilterValue.slug,
            CategoryFilterValue.sort_order.label("value_sort_order"),
        )
        .join(
            CategoryFilterValue,
            CategoryFilterValue.filter_id == CategoryFilterDefinition.id,
        )
        .filter(
            CategoryFilterDefinition.is_active.is_(True),
            CategoryFilterValue.is_active.is_(True),
        )
    )

    if filter_category_ids:
        custom_filter_query = custom_filter_query.filter(
            CategoryFilterDefinition.category_id.in_(filter_category_ids)
        )
    else:
        custom_filter_query = custom_filter_query.filter(False)

    rows = custom_filter_query.order_by(
        CategoryFilterDefinition.sort_order,
        CategoryFilterDefinition.id,
        CategoryFilterValue.sort_order,
        CategoryFilterValue.id,
    ).all()

    for (
        definition_id,
        name,
        filter_type,
        definition_sort,
        value_id,
        label,
        slug,
        value_sort,
    ) in rows:
        add_group(
            definition_id,
            name,
            filter_type,
            definition_sort,
            [{
                "id": value_id,
                "label": label,
                "slug": slug,
                "sort_order": value_sort,
            }],
        )

    # Server-owned standard dimensions are also narrowed to the current
    # product scope. This is what prevents a side/circle result from showing
    # unrelated colors, sizes, or brands.
    scoped_product_ids = db.session.query(product_scope.c.id)

    color_ids = [
        int(value_id)
        for (value_id,) in (
            db.session.query(ProductVariant.color_id)
            .filter(
                ProductVariant.product_id.in_(scoped_product_ids),
                ProductVariant.color_id.isnot(None),
                ProductVariant.is_active.is_(True),
            )
            .distinct()
            .all()
        )
    ]
    color_ids += [
        int(value_id)
        for (value_id,) in (
            db.session.query(ProductColorReference.color_id)
            .filter(
                ProductColorReference.product_id.in_(scoped_product_ids),
            )
            .distinct()
            .all()
        )
    ]
    color_ids += [
        int(value_id)
        for (value_id,) in (
            db.session.query(ProductMedia.color_id)
            .filter(
                ProductMedia.product_id.in_(scoped_product_ids),
                ProductMedia.color_id.isnot(None),
            )
            .distinct()
            .all()
        )
    ]
    color_ids = sorted(set(color_ids))
    if color_ids:
        colors = (
            Color.query
            .filter(
                Color.id.in_(color_ids),
                Color.is_active.is_(True),
            )
            .order_by(Color.sort_order, Color.name, Color.id)
            .all()
        )
        add_group(
            None,
            "اللون",
            "color",
            10,
            [
                {
                    "id": -(_COLOR_FILTER_OFFSET + int(color.id)),
                    "label": color.name,
                    "slug": color.name,
                    "sort_order": color.sort_order,
                }
                for color in colors
            ],
        )

    size_ids = [
        int(value_id)
        for (value_id,) in (
            db.session.query(ProductVariant.size_id)
            .filter(
                ProductVariant.product_id.in_(scoped_product_ids),
                ProductVariant.size_id.isnot(None),
                ProductVariant.is_active.is_(True),
            )
            .distinct()
            .all()
        )
    ]
    size_ids += [
        int(value_id)
        for (value_id,) in (
            db.session.query(ProductSizeReference.size_id)
            .filter(
                ProductSizeReference.product_id.in_(scoped_product_ids),
            )
            .distinct()
            .all()
        )
    ]
    size_ids += [
        int(value_id)
        for (value_id,) in (
            db.session.query(ProductOptionValue.size_id)
            .join(ProductOption, ProductOption.id == ProductOptionValue.option_id)
            .filter(
                ProductOption.product_id.in_(scoped_product_ids),
                ProductOptionValue.size_id.isnot(None),
            )
            .distinct()
            .all()
        )
    ]
    size_ids = sorted(set(size_ids))
    if size_ids:
        sizes = (
            Size.query
            .filter(
                Size.id.in_(size_ids),
                Size.is_active.is_(True),
            )
            .order_by(Size.group, Size.sort_order, Size.label, Size.id)
            .all()
        )
        add_group(
            None,
            "المقاس",
            "size",
            20,
            [
                {
                    "id": -(_SIZE_FILTER_OFFSET + int(size.id)),
                    "label": size.label,
                    "slug": f"{size.group}-{size.code}",
                    "sort_order": size.sort_order,
                }
                for size in sizes
            ],
        )

    brand_ids = [
        int(value_id)
        for (value_id,) in (
            db.session.query(Product.brand_id)
            .filter(
                Product.id.in_(scoped_product_ids),
                Product.brand_id.isnot(None),
            )
            .distinct()
            .all()
        )
    ]
    if brand_ids:
        brands = (
            Brand.query
            .filter(
                Brand.id.in_(brand_ids),
                Brand.is_active.is_(True),
            )
            .order_by(Brand.name, Brand.id)
            .all()
        )
        add_group(
            None,
            "العلامة التجارية",
            "brand",
            30,
            [
                {
                    "id": -(_BRAND_FILTER_OFFSET + int(brand.id)),
                    "label": brand.name,
                    "slug": brand.slug,
                    "sort_order": index,
                }
                for index, brand in enumerate(brands)
            ],
        )

    # Category descendants remain a useful filter for normal category result
    # pages. Side/circle pages deliberately do not inherit their root.
    side_scoped = bool(side_category_id or circle_id)
    if category_scope_ids and not side_scoped:
        descendant_ids = {
            int(descendant_id)
            for scope_id in category_scope_ids
            for descendant_id in CatalogService.category_descendant_ids(scope_id)
            if int(descendant_id) != int(scope_id)
        }
        if descendant_ids:
            descendant_rows = (
                Category.query
                .filter(
                    Category.is_active.is_(True),
                    Category.id.in_(sorted(descendant_ids)),
                )
                .order_by(
                    Category.parent_id,
                    Category.sort_order,
                    Category.name,
                    Category.id,
                )
                .all()
            )
            add_group(
                None,
                "الفئة",
                "category",
                5,
                [
                    {
                        "id": -(_CATEGORY_FILTER_OFFSET + int(row.id)),
                        "label": row.name,
                        "slug": row.slug,
                        "sort_order": row.sort_order,
                    }
                    for row in descendant_rows
                ],
            )

    items = list(merged.values())
    items.sort(key=lambda item: (
        int(item.get("sort_order") or 0),
        str(item.get("name") or "").casefold(),
    ))
    return {"items": items}


@api_bp.post("/categories/<int:category_id>/filters")
@admin_api_required("category.manage")
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
    include_descendants = str(
        request.args.get("include_descendants", "")
    ).strip().lower() in {"1", "true", "yes"}
    try:
        return {
            "items": CatalogService.category_filters(
                category_id,
                include_descendants=include_descendants,
            )
        }
    except LookupError as exc:
        return {"error": "category_not_found", "detail": str(exc)}, 404


@api_bp.post("/filters/<int:filter_id>/values")
@admin_api_required("category.manage")
def create_filter_value(filter_id):
    payload = request.get_json(silent=True) or {}
    try:
        return {"item": CatalogService.create_filter_value(filter_id, payload)}, 201
    except LookupError as exc:
        return {"error": "filter_not_found", "detail": str(exc)}, 404
    except ValueError as exc:
        return {"error": "filter_value_creation_failed", "detail": str(exc)}, 400


@api_bp.post("/products/<int:product_id>/filter-values")
@admin_api_required("product.edit")
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
@admin_api_required("product.edit")
def create_color():
    payload = request.get_json(silent=True) or {}
    try:
        from ...extensions import db
        from ...models import Color
        name = str(payload.get("name") or "").strip()
        if not name:
            raise ValueError("اسم اللون مطلوب.")
        hex_code = (payload.get("hex_code") or "").strip() or None
        duplicate = Color.query.filter(Color.name == name, Color.is_active.is_(True)).first()
        if duplicate:
            raise ValueError("هذا اللون موجود مسبقًا.")
        color = Color(
            name=name,
            hex_code=hex_code,
            swatch_asset_id=payload.get("swatch_asset_id"),
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(color)
        db.session.commit()
        return {"item": {
            "id": color.id,
            "name": color.name,
            "hex_code": color.hex_code,
            "swatch_asset_id": color.swatch_asset_id,
        }}, 201
    except (KeyError, TypeError, ValueError) as exc:
        db.session.rollback() if "db" in locals() else None
        return {"error": "invalid_color", "detail": str(exc)}, 400


@api_bp.post("/reference/sizes")
@admin_api_required("product.edit")
def create_size():
    payload = request.get_json(silent=True) or {}
    try:
        from ...extensions import db
        from ...models import Size
        group = str(payload.get("group") or "").strip()
        code = str(payload.get("code") or "").strip().upper()
        label = str(payload.get("label") or "").strip()
        if not group or not code or not label:
            raise ValueError("مجموعة المقاس والكود والاسم الظاهر مطلوبة.")
        if Size.query.filter_by(group=group, code=code).first():
            raise ValueError("كود المقاس مستخدم داخل المجموعة.")
        size = Size(
            group=group,
            code=code,
            label=label,
            sort_order=int(payload.get("sort_order", 0)),
        )
        db.session.add(size)
        db.session.commit()
        return {"item": {"id": size.id, "group": size.group, "code": size.code, "label": size.label}}, 201
    except (KeyError, TypeError, ValueError) as exc:
        db.session.rollback() if "db" in locals() else None
        return {"error": "invalid_size", "detail": str(exc)}, 400


@api_bp.get("/reference/policies")
def policy_references():
    from ...models import ReturnPolicy, ShippingPolicy, WarrantyPolicy
    return {
        "shipping": [{"id": x.id, "name": x.name, "delivery_window": x.delivery_window} for x in ShippingPolicy.query.filter_by(is_active=True).order_by(ShippingPolicy.name).all()],
        "return": [{"id": x.id, "name": x.name, "return_window_days": x.return_window_days} for x in ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.name).all()],
        "warranty": [{"id": x.id, "name": x.name, "duration_days": x.duration_days} for x in WarrantyPolicy.query.filter_by(is_active=True).order_by(WarrantyPolicy.name).all()],
    }


@api_bp.post("/reference/brands")
@admin_api_required("product.edit")
def create_brand_reference():
    from ...extensions import db
    from ...models import Brand
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    if not name:
        return {"error": "invalid_brand", "detail": "اسم العلامة التجارية مطلوب."}, 400
    slug = str(payload.get("slug") or "").strip().lower()
    if not slug:
        from .services import _slugify
        slug = _slugify(name, fallback="brand")
    base_slug = slug
    index = 2
    while Brand.query.filter_by(slug=slug).first() is not None:
        slug = f"{base_slug}-{index}"[:180]
        index += 1
    row = Brand(name=name, slug=slug, logo_asset_id=payload.get("logo_asset_id"))
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "slug": row.slug, "is_active": bool(row.is_active)}}, 201


@api_bp.post("/reference/hashtags")
@admin_api_required("product.edit")
def create_hashtag_reference():
    from ...extensions import db
    from ...models import Hashtag
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    display_name = str(payload.get("display_name") or "").strip() or None
    if not name:
        return {"error": "invalid_hashtag", "detail": "اسم الهاشتاج مطلوب."}, 400
    slug = str(payload.get("slug") or "").strip().lower()
    if not slug:
        from .services import _slugify
        slug = _slugify(display_name or name, fallback="tag")
    base_slug = slug
    index = 2
    while Hashtag.query.filter_by(slug=slug).first() is not None:
        slug = f"{base_slug}-{index}"[:180]
        index += 1
    row = Hashtag(name=name, slug=slug, display_name=display_name, sort_order=int(payload.get("sort_order", 0)))
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "slug": row.slug, "display_name": row.display_name, "is_active": bool(row.is_active)}}, 201


@api_bp.get("/trends")
def public_trends():
    limit = min(max(request.args.get("limit", 20, type=int), 1), 50)
    return {
        "items": CatalogService.list_public_trends(limit=limit),
        "hashtags": CatalogService.list_public_trend_hashtags(limit=500),
        "settings": CatalogService.trend_display_settings(),
        # Keep trend-product cards on the same global storefront configuration
        # used by the home/product grids.
        "product_card_settings": CatalogService.product_card_display_settings(),
    }


@api_bp.get("/trends/<int:trend_id>")
def public_trend_detail(trend_id):
    from ...models import Trend
    trend = db.session.get(Trend, trend_id)
    if (
        trend is None
        or not trend.is_active
        or trend.status != "active"
        or CatalogService.is_trend_timer_expired(trend)
    ):
        return {"error": "not_found", "detail": "trend not found"}, 404
    payload = CatalogService.serialize_public_trend(trend)
    if not payload["hashtag"] or not payload["background"] or len(payload["products"]) != 3:
        return {"error": "not_found", "detail": "trend not available"}, 404
    return {"item": payload}


@api_bp.get("/reference/hashtag-products")
@admin_api_required("product.edit")
def hashtag_product_references():
    hashtag_id = request.args.get("hashtag_id", type=int)
    if not hashtag_id:
        return {"error": "invalid_hashtag", "detail": "معرّف الهاشتاج مطلوب."}, 400
    try:
        items = CatalogService.trend_product_candidates(hashtag_id, limit=request.args.get("limit", 100, type=int) or 100)
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
    return {"items": items}


@api_bp.post("/reference/promotional-strips")
@admin_api_required("product.edit")
def create_promotional_strip_reference():
    from ...extensions import db
    from ...models import PromotionalStrip
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    text_body = str(payload.get("text_body") or "").strip()
    if not name or not text_body:
        return {"error": "invalid_promotional_strip", "detail": "اسم الشريط والنص مطلوبان."}, 400
    row = PromotionalStrip(
        name=name,
        text_prefix=str(payload.get("text_prefix") or "").strip() or None,
        text_body=text_body,
        background_color=str(payload.get("background_color") or "").strip() or None,
        text_color=str(payload.get("text_color") or "").strip() or None,
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "text_body": row.text_body, "is_active": bool(row.is_active)}}, 201


@api_bp.post("/reference/campaigns")
@admin_api_required("product.edit")
def create_campaign_reference():
    from ...extensions import db
    from ...models import Campaign, Badge
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name") or "").strip()
    if not name:
        return {"error": "invalid_campaign", "detail": "اسم الحملة مطلوب."}, 400
    slug = str(payload.get("slug") or "").strip().lower()
    if not slug:
        from .services import _slugify
        slug = _slugify(name, fallback="campaign")
    base_slug = slug
    index = 2
    while Campaign.query.filter_by(slug=slug).first() is not None:
        slug = f"{base_slug}-{index}"[:200]
        index += 1
    badge_id = payload.get("badge_id")
    if badge_id not in (None, "") and db.session.get(Badge, int(badge_id)) is None:
        return {"error": "invalid_campaign", "detail": "الشارة المختارة غير موجودة."}, 400
    row = Campaign(
        name=name,
        slug=slug,
        badge_id=int(badge_id) if badge_id not in (None, "") else None,
        status=str(payload.get("status") or "draft").strip(),
        display_priority=int(payload.get("display_priority", 0)),
    )
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "name": row.name, "slug": row.slug, "status": row.status, "is_active": bool(row.is_active)}}, 201


@api_bp.post("/policies/shipping")
@admin_api_required("policy.manage")
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
@admin_api_required("policy.manage")
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
@admin_api_required("policy.manage")
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
@admin_api_required("product.edit")
def create_badge():
    from ...extensions import db
    from ...models import Badge
    payload = request.get_json(silent=True) or {}
    try:
        name = str(payload.get("name") or "").strip()
        code = str(payload.get("code") or "").strip().lower()
        if not name or not code:
            raise ValueError("اسم الشارة والكود مطلوبان.")
        if Badge.query.filter_by(code=code).first():
            raise ValueError("كود الشارة مستخدم مسبقًا.")
        storefront_tab = (payload.get("storefront_tab") or "none").strip().lower()
        if storefront_tab not in {"none", "new", "offers"}:
            raise ValueError("تبويب الشارة يجب أن يكون none أو new أو offers.")
        row = Badge(
            name=name,
            code=code,
            icon_asset_id=payload.get("icon_asset_id"),
            bg_color=(payload.get("bg_color") or "").strip() or None,
            text_color=(payload.get("text_color") or "").strip() or None,
            style=(payload.get("style") or "solid").strip(),
            storefront_tab=storefront_tab,
            priority=int(payload.get("priority", 0)),
        )
        db.session.add(row)
        db.session.commit()
        return {"item": {
            "id": row.id, "name": row.name, "code": row.code,
            "bg_color": row.bg_color, "text_color": row.text_color,
            "style": row.style, "storefront_tab": row.storefront_tab,
            "priority": row.priority,
        }}, 201
    except (TypeError, ValueError) as exc:
        db.session.rollback()
        return {"error": "invalid_badge", "detail": str(exc)}, 400


@api_bp.post("/size-guides")
@admin_api_required("product.edit")
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
@admin_api_required("product.edit")
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


@api_bp.delete("/products/<int:product_id>/media/<int:media_id>")
@admin_api_required("product.edit")
def delete_product_media(product_id, media_id):
    try:
        return {"item": CatalogService.remove_product_media(product_id, media_id)}
    except LookupError as exc:
        return {"error": "not_found", "detail": str(exc)}, 404
