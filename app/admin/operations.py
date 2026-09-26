from decimal import Decimal, InvalidOperation

from flask import render_template, request

from ..extensions import db
from ..models import (
    Banner,
    Campaign,
    Currency,
    PricingGroup,
    PricingGroupRule,
    PricingGroupCity,
    CustomerPricingAssignment,
    Customer,
    Region,
    City,
    Hashtag,
    Category,
    Product,
    BannerTarget,
    MediaAsset,
    Badge,
    ShippingPolicy,
    ReturnPolicy,
    WarrantyPolicy,
    Look,
    LookProduct,
)
from ..services.pricing import PricingRule, calculate_customer_price
from .context import build_admin_context
from ..modules.catalog.services import MediaService


def register_operation_routes(admin_bp):
    @admin_bp.route("/catalog/policies", methods=["GET", "POST"])
    def catalog_policies():
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "").strip()
                if action.startswith("badge_"):
                    row = db.session.get(Badge, request.form.get("id", type=int))
                    if action == "badge_create":
                        name = (request.form.get("name") or "").strip(); code = (request.form.get("code") or "").strip().lower()
                        if not name or not code: raise ValueError("اسم الشارة والكود مطلوبان.")
                        if Badge.query.filter_by(code=code).first(): raise ValueError("كود الشارة مستخدم مسبقًا.")
                        icon_id = None; file = request.files.get("icon_file")
                        if file and file.filename:
                            assets = MediaService.save_generic_files([file], "badges"); icon_id = assets[0]["id"] if assets else None
                        db.session.add(Badge(name=name, code=code, icon_asset_id=icon_id, bg_color=request.form.get("bg_color") or None, text_color=request.form.get("text_color") or None, style=request.form.get("style") or "solid", priority=request.form.get("priority", 0, type=int)))
                        success = "تمت إضافة الشارة."
                    elif row is None: raise ValueError("الشارة غير موجودة.")
                    elif action == "badge_archive": row.is_active = False; success = "تمت أرشفة الشارة."
                    else:
                        name=(request.form.get("name") or "").strip(); code=(request.form.get("code") or "").strip().lower()
                        if not name or not code: raise ValueError("اسم الشارة والكود مطلوبان.")
                        if Badge.query.filter(Badge.id != row.id, Badge.code == code).first(): raise ValueError("كود الشارة مستخدم مسبقًا.")
                        row.name=name; row.code=code; row.bg_color=request.form.get("bg_color") or None; row.text_color=request.form.get("text_color") or None; row.style=request.form.get("style") or "solid"; row.priority=request.form.get("priority", 0, type=int); success="تم تحديث الشارة."
                else:
                    kind = action.split("_", 1)[0]
                    model = {"shipping": ShippingPolicy, "return": ReturnPolicy, "warranty": WarrantyPolicy}.get(kind)
                    if model is None: raise ValueError("إجراء السياسة غير معروف.")
                    row = db.session.get(model, request.form.get("id", type=int))
                    if action.endswith("_create"):
                        name=(request.form.get("name") or "").strip()
                        if not name: raise ValueError("اسم السياسة مطلوب.")
                        if kind == "shipping": row=ShippingPolicy(name=name, free_shipping_enabled=request.form.get("free_shipping_enabled")=="on", min_order_amount=request.form.get("min_order_amount") or None, promo_text=request.form.get("promo_text") or None, delivery_window=request.form.get("delivery_window") or None)
                        elif kind == "return": row=ReturnPolicy(name=name, return_window_days=request.form.get("return_window_days",0,type=int), conditions=request.form.get("conditions") or None, fee_rule=request.form.get("fee_rule") or None, refund_method=request.form.get("refund_method") or None)
                        else: row=WarrantyPolicy(name=name, duration_days=request.form.get("duration_days",0,type=int), coverage=request.form.get("coverage") or None, exclusions=request.form.get("exclusions") or None, claim_method=request.form.get("claim_method") or None)
                        db.session.add(row); success="تمت إضافة السياسة."
                    elif row is None: raise ValueError("السياسة غير موجودة.")
                    elif action.endswith("_archive"): row.is_active=False; success="تمت أرشفة السياسة."
                    else:
                        row.name=(request.form.get("name") or "").strip()
                        if not row.name: raise ValueError("اسم السياسة مطلوب.")
                        if kind == "shipping": row.free_shipping_enabled=request.form.get("free_shipping_enabled")=="on"; row.min_order_amount=request.form.get("min_order_amount") or None; row.promo_text=request.form.get("promo_text") or None; row.delivery_window=request.form.get("delivery_window") or None
                        elif kind == "return": row.return_window_days=request.form.get("return_window_days",0,type=int); row.conditions=request.form.get("conditions") or None; row.fee_rule=request.form.get("fee_rule") or None; row.refund_method=request.form.get("refund_method") or None
                        else: row.duration_days=request.form.get("duration_days",0,type=int); row.coverage=request.form.get("coverage") or None; row.exclusions=request.form.get("exclusions") or None; row.claim_method=request.form.get("claim_method") or None
                        success="تم تحديث السياسة."
                db.session.commit()
            except (ValueError, TypeError, OSError) as exc:
                db.session.rollback(); error=str(exc)
        return render_template("admin/catalog_policies.html", title="الشارات والسياسات", badges=Badge.query.filter_by(is_active=True).order_by(Badge.priority.desc(),Badge.name).all(), shipping_policies=ShippingPolicy.query.filter_by(is_active=True).order_by(ShippingPolicy.name).all(), return_policies=ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.name).all(), warranty_policies=WarrantyPolicy.query.filter_by(is_active=True).order_by(WarrantyPolicy.name).all(), success=success, error=error, **build_admin_context())

    @admin_bp.route("/pricing/preview", methods=["GET", "POST"])
    def pricing_preview_page():
        context = _ctx()
        result = None
        error = None
        if request.method == "POST":
            try:
                result = calculate_customer_price(
                    Decimal(request.form["base_price_sar"]),
                    Decimal(request.form["fx_rate"]),
                    PricingRule(
                        Decimal(request.form.get("percent_markup", "0")),
                        Decimal(request.form.get("fixed_markup", "0")),
                        int(request.form.get("decimals", "2")),
                        request.form.get("rounding_rule", "nearest"),
                    ),
                )
            except (KeyError, InvalidOperation, ValueError) as exc:
                error = str(exc)
        return render_template(
            "admin/pricing_preview.html",
            title="معاينة السعر",
            result=result,
            error=error,
            **context,
        )

    @admin_bp.route("/banners", methods=["GET", "POST"])
    def banners():
        context = _ctx()
        error = None
        success = None
        positions = {
            "top_left": "أعلى اليسار",
            "top_center": "أعلى الوسط",
            "top_right": "أعلى اليمين",
            "center_left": "وسط اليسار",
            "center": "الوسط",
            "center_right": "وسط اليمين",
            "bottom_left": "أسفل اليسار",
            "bottom_center": "أسفل الوسط",
            "bottom_right": "أسفل اليمين",
        }
        target_types = {
            "campaign": Campaign,
            "category": Category,
            "hashtag": Hashtag,
            "product": Product,
            "style_tab": Look,
        }
        def color(value, default):
            value = (value or default).strip()
            import re
            if not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
                raise ValueError("اللون يجب أن يكون بصيغة HEX مثل #111827.")
            return value

        if request.method == "POST":
            try:
                action = (request.form.get("action") or "create_banner").strip()
                row = db.session.get(Banner, request.form.get("id", type=int))

                if action in {"create_banner", "update_banner"}:
                    name = (request.form.get("name") or "").strip()
                    if not name:
                        raise ValueError("اسم البانر مطلوب.")
                    image = request.files.get("image_file")
                    mobile = request.files.get("mobile_image_file")
                    if action == "create_banner" and (not image or not image.filename):
                        raise ValueError("الصورة الأساسية مطلوبة.")
                    if action == "update_banner" and row is None:
                        raise ValueError("البانر غير موجود.")

                    root_category_id = request.form.get("root_category_id", type=int) or None
                    if root_category_id is not None:
                        root = db.session.get(Category, root_category_id)
                        if root is None or not root.is_active or root.parent_id is not None:
                            raise ValueError("الفئة الأساسية يجب أن تكون فئة أب بلا أب.")
                    duration = request.form.get("duration", type=int) or 6
                    if duration < 1 or duration > 120:
                        raise ValueError("مدة ظهور البانر يجب أن تكون بين 1 و120 ثانية.")
                    status = (request.form.get("status") or "draft").strip()
                    if status not in {"draft", "active"}:
                        raise ValueError("حالة البانر غير صحيحة.")
                    position_text = (request.form.get("position_text") or "center").strip()
                    if position_text not in positions:
                        raise ValueError("موضع النص غير مدعوم.")
                    opacity = _decimal(request.form.get("overlay_opacity"), "0")
                    if opacity < 0 or opacity > 1:
                        raise ValueError("شفافية الخلفية يجب أن تكون بين 0 و1.")

                    values = {
                        "name": name,
                        "root_category_id": root_category_id,
                        "title": (request.form.get("title") or "").strip() or None,
                        "description": (request.form.get("description") or "").strip() or None,
                        "button_label": (request.form.get("button_label") or "").strip() or None,
                        "title_color": color(request.form.get("title_color"), "#ffffff"),
                        "description_color": color(request.form.get("description_color"), "#ffffff"),
                        "button_text_color": color(request.form.get("button_text_color"), "#ffffff"),
                        "button_background_color": color(request.form.get("button_background_color"), "#111827"),
                        "overlay_background_color": color(request.form.get("overlay_background_color"), "#111827"),
                        "overlay_opacity": opacity,
                        "size_spec": (request.form.get("size_spec") or "").strip() or None,
                        "overlay_text": (request.form.get("overlay_text") or "").strip() or None,
                        "position_text": position_text,
                        "duration": duration,
                        "sort_order": request.form.get("sort_order", 0, type=int) or 0,
                        "status": status,
                    }
                    starts_raw = (request.form.get("starts_at") or "").strip()
                    ends_raw = (request.form.get("ends_at") or "").strip()
                    from datetime import datetime, timezone
                    def parse_dt(value):
                        if not value:
                            return None
                        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
                        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
                    values["starts_at"] = parse_dt(starts_raw)
                    values["ends_at"] = parse_dt(ends_raw)
                    if values["starts_at"] and values["ends_at"] and values["ends_at"] < values["starts_at"]:
                        raise ValueError("نهاية الجدولة يجب أن تكون بعد البداية.")

                    if action == "create_banner":
                        assets = MediaService.save_generic_files(
                            [image] + ([mobile] if mobile and mobile.filename else []),
                            "banners",
                        )
                        if not assets:
                            raise ValueError("تعذر معالجة صورة البانر.")
                        values["image_asset_id"] = assets[0]["id"]
                        values["mobile_asset_id"] = assets[1]["id"] if len(assets) > 1 else None
                        row = Banner(**values)
                        db.session.add(row)
                        success = "تم إنشاء البانر."
                    else:
                        for key, value in values.items():
                            setattr(row, key, value)
                        if image and image.filename:
                            assets = MediaService.save_generic_files([image], "banners")
                            if assets:
                                row.image_asset_id = assets[0]["id"]
                        if mobile and mobile.filename:
                            assets = MediaService.save_generic_files([mobile], "banners")
                            if assets:
                                row.mobile_asset_id = assets[0]["id"]
                        success = "تم تحديث البانر."

                elif action == "add_targets":
                    banner_id = request.form.get("banner_id", type=int)
                    banner = db.session.get(Banner, banner_id)
                    if banner is None:
                        raise ValueError("البانر غير موجود.")
                    target_type = (request.form.get("target_type") or "").strip()
                    include_descendants = request.form.get("include_descendants") == "on"
                    target_ids = [int(x) for x in request.form.getlist("target_id") if str(x).isdigit()]
                    if target_type == "url":
                        url = (request.form.get("target_url") or "").strip()
                        if not url:
                            raise ValueError("الرابط مطلوب.")
                        target_ids = [None]
                    elif target_type == "style_tab":
                        url = (request.form.get("target_url") or "/looks").strip() or "/looks"
                        target_ids = [int(x) for x in request.form.getlist("target_id") if str(x).isdigit()] or [None]
                    elif target_type not in target_types:
                        raise ValueError("نوع هدف البانر غير صحيح.")
                    elif not target_ids:
                        raise ValueError("اختر هدفًا واحدًا على الأقل.")
                    created = 0
                    for target_id in target_ids:
                        if target_type in target_types and db.session.get(target_types[target_type], target_id) is None:
                            continue
                        config = {"include_descendants": include_descendants} if target_type == "category" else {}
                        db.session.add(
                            BannerTarget(
                                banner_id=banner.id,
                                target_type=target_type,
                                target_id=target_id,
                                url=url if target_type in {"url", "style_tab"} else None,
                                config_json=config,
                                priority=request.form.get("target_priority", 0, type=int) or 0,
                            )
                        )
                        created += 1
                    if not created:
                        raise ValueError("لم يتم العثور على أهداف صحيحة.")
                    success = f"تم ربط {created} هدف."

                elif action == "add_target":
                    # Backward-compatible single-target action.
                    banner_id = request.form.get("banner_id", type=int)
                    target_type = (request.form.get("target_type") or "").strip()
                    target_id = request.form.get("target_id", type=int)
                    if target_type == "url":
                        target_id = None
                        url = (request.form.get("target_url") or "").strip()
                    elif target_type == "style_tab":
                        target_id = request.form.get("target_id", type=int)
                        url = (request.form.get("target_url") or "/looks").strip()
                    elif target_type in target_types and db.session.get(target_types[target_type], target_id):
                        url = None
                    else:
                        raise ValueError("هدف البانر غير صحيح.")
                    if target_type in {"url", "style_tab"} and not url:
                        raise ValueError("الرابط مطلوب.")
                    db.session.add(BannerTarget(
                        banner_id=banner_id,
                        target_type=target_type,
                        target_id=target_id,
                        url=url,
                        config_json={"include_descendants": request.form.get("include_descendants") == "on"} if target_type == "category" else {},
                        priority=request.form.get("target_priority", 0, type=int),
                    ))
                    success = "تم ربط الهدف."

                elif action == "delete_target":
                    target = db.session.get(BannerTarget, request.form.get("target_id", type=int))
                    if target is None:
                        raise ValueError("هدف البانر غير موجود.")
                    db.session.delete(target)
                    success = "تم حذف الهدف."

                elif action == "archive_banner":
                    if row is None:
                        raise ValueError("البانر غير موجود.")
                    row.is_active = False
                    success = "تمت أرشفة البانر."

                elif action == "banner_reorder":
                    ids = [int(x) for x in (request.form.get("order_ids") or "").split(",") if x.strip().isdigit()]
                    for index, banner_id in enumerate(ids):
                        banner = db.session.get(Banner, banner_id)
                        if banner and banner.is_active:
                            banner.sort_order = index
                    success = "تم حفظ ترتيب البانرات."

                else:
                    raise ValueError("إجراء البانر غير معروف.")
                db.session.commit()
            except (ValueError, OSError, TypeError, InvalidOperation) as exc:
                db.session.rollback()
                error = str(exc)

        banners = Banner.query.filter_by(is_active=True).order_by(
            Banner.sort_order, Banner.id.desc()
        ).limit(200).all()
        ids = [x.id for x in banners]
        asset_ids = []
        for x in banners:
            asset_ids.append(x.image_asset_id)
            if x.mobile_asset_id:
                asset_ids.append(x.mobile_asset_id)
        assets = MediaAsset.query.filter(MediaAsset.id.in_(asset_ids)).all() if asset_ids else []
        asset_map = {x.id: x for x in assets}
        targets = BannerTarget.query.filter(
            BannerTarget.banner_id.in_(ids)
        ).order_by(BannerTarget.priority.desc(), BannerTarget.id.desc()).all() if ids else []
        targets_by_banner = {}
        for target in targets:
            targets_by_banner.setdefault(target.banner_id, []).append(target)
        categories = Category.query.filter_by(is_active=True).order_by(Category.sort_order, Category.name).limit(1000).all()
        root_categories = [x for x in categories if x.parent_id is None]
        category_children = {}
        for item in categories:
            category_children.setdefault(item.parent_id, []).append(item)
        campaigns = Campaign.query.filter_by(is_active=True).order_by(Campaign.display_priority.desc(), Campaign.name).limit(300).all()
        hashtags = Hashtag.query.filter_by(is_active=True).order_by(Hashtag.sort_order, Hashtag.name).limit(300).all()
        products = Product.query.filter(Product.is_active.is_(True), Product.status != "archived").order_by(Product.id.desc()).limit(300).all()
        category_map = {x.id: x.name for x in categories}
        campaign_map = {x.id: x.name for x in campaigns}
        hashtag_map = {x.id: x.name for x in hashtags}
        product_map = {x.id: x.name for x in products}
        looks_rows = Look.query.filter_by(is_active=True).order_by(Look.sort_order, Look.name).limit(200).all()
        look_map = {x.id: x.name for x in looks_rows}
        category_target_keys = {
            banner.id: [f"category:{x.target_id}" for x in targets_by_banner.get(banner.id, []) if x.target_type == "category"]
            for banner in banners
        }
        return render_template(
            "admin/banners.html",
            title="البانرات",
            banners=banners,
            asset_map=asset_map,
            targets_by_banner=targets_by_banner,
            categories=categories,
            root_categories=root_categories,
            category_children=category_children,
            campaigns=campaigns,
            hashtags=hashtags,
            products=products,
            category_target_keys=category_target_keys,
            category_map=category_map,
            campaign_map=campaign_map,
            hashtag_map=hashtag_map,
            product_map=product_map,
            looks=looks_rows,
            look_map=look_map,
            positions=positions,
            success=success,
            error=error,
            **context,
        )

    @admin_bp.route("/looks", methods=["GET", "POST"])
    def looks():
        context = _ctx()
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "look_create").strip()
                look = db.session.get(Look, request.form.get("id", type=int))
                if action in {"look_create", "look_update"}:
                    from .entity_views import _unique_slug
                    name = (request.form.get("name") or "").strip()
                    if not name:
                        raise ValueError("اسم الإطلالة مطلوب.")
                    slug = (request.form.get("slug") or "").strip().lower()
                    if action == "look_create":
                        slug = slug or _unique_slug(Look, name, fallback="look")
                        if Look.query.filter_by(slug=slug).first():
                            raise ValueError("Slug الإطلالة مستخدم مسبقًا.")
                        look = Look(name=name, slug=slug)
                        db.session.add(look)
                    else:
                        if look is None:
                            raise ValueError("الإطلالة غير موجودة.")
                        slug = slug or _unique_slug(Look, name, exclude_id=look.id, fallback="look")
                        duplicate = Look.query.filter(Look.id != look.id, Look.slug == slug).first()
                        if duplicate:
                            raise ValueError("Slug الإطلالة مستخدم مسبقًا.")
                    look.name = name
                    look.slug = slug
                    look.description = (request.form.get("description") or "").strip() or None
                    look.status = (request.form.get("status") or "draft").strip()
                    look.sort_order = request.form.get("sort_order", 0, type=int) or 0
                    cover = request.files.get("cover_image")
                    if cover and cover.filename:
                        assets = MediaService.save_generic_files([cover], "looks")
                        if assets:
                            look.cover_asset_id = assets[0]["id"]
                    success = "تم تحديث الإطلالة." if action == "look_update" else "تم إنشاء الإطلالة."
                elif action == "look_archive":
                    if look is None:
                        raise ValueError("الإطلالة غير موجودة.")
                    look.is_active = False
                    success = "تمت أرشفة الإطلالة."
                elif action in {"look_add_product", "look_remove_product"}:
                    look_id = request.form.get("look_id", type=int)
                    product_id = request.form.get("product_id", type=int)
                    if db.session.get(Look, look_id) is None or db.session.get(Product, product_id) is None:
                        raise ValueError("الإطلالة أو المنتج غير موجود.")
                    if action == "look_add_product":
                        if not LookProduct.query.filter_by(look_id=look_id, product_id=product_id).first():
                            db.session.add(LookProduct(
                                look_id=look_id,
                                product_id=product_id,
                                sort_order=request.form.get("sort_order", 0, type=int) or 0,
                            ))
                        success = "تمت إضافة المنتج إلى الإطلالة."
                    else:
                        row = LookProduct.query.filter_by(look_id=look_id, product_id=product_id).first()
                        if row:
                            db.session.delete(row)
                        success = "تمت إزالة المنتج من الإطلالة."
                else:
                    raise ValueError("إجراء الإطلالة غير معروف.")
                db.session.commit()
            except (ValueError, OSError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        looks_rows = Look.query.filter_by(is_active=True).order_by(Look.sort_order, Look.id.desc()).all()
        assets = MediaAsset.query.filter(MediaAsset.id.in_([x.cover_asset_id for x in looks_rows if x.cover_asset_id])).all()
        asset_map = {x.id: x for x in assets}
        products = Product.query.filter(Product.is_active.is_(True), Product.status != "archived").order_by(Product.id.desc()).limit(500).all()
        product_map = {x.id: x for x in products}
        look_product_rows = LookProduct.query.filter(LookProduct.look_id.in_([x.id for x in looks_rows])).order_by(LookProduct.sort_order, LookProduct.id).all() if looks_rows else []
        products_by_look = {}
        for item in look_product_rows:
            if item.product_id in product_map:
                products_by_look.setdefault(item.look_id, []).append(item)
        return render_template(
            "admin/looks.html",
            title="الإطلالات",
            section="المحتوى والمتجر",
            looks=looks_rows,
            asset_map=asset_map,
            products=products,
            product_map=product_map,
            products_by_look=products_by_look,
            success=success,
            error=error,
            **context,
        )

    @admin_bp.route("/campaigns", methods=["GET", "POST"])
    def campaigns():
        from .entity_views import _unique_slug
        context=_ctx(); error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(Campaign,request.form.get("id",type=int))
                if action=="create":
                    name=(request.form.get("name") or "").strip()
                    if not name: raise ValueError("اسم الحملة مطلوب.")
                    slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Campaign,name,fallback="campaign")
                    if Campaign.query.filter_by(slug=slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    db.session.add(Campaign(name=name,slug=slug,start_at=None,end_at=None,status=(request.form.get("status") or "draft").strip(),display_priority=request.form.get("display_priority",0,type=int))); success="تم إنشاء الحملة."
                elif row is None: raise ValueError("الحملة غير موجودة.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة الحملة."
                elif action=="update":
                    name=(request.form.get("name") or "").strip(); slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Campaign,name,exclude_id=row.id,fallback="campaign")
                    if not name: raise ValueError("اسم الحملة مطلوب.")
                    if Campaign.query.filter(Campaign.id!=row.id,Campaign.slug==slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    row.name=name; row.slug=slug; row.status=(request.form.get("status") or row.status).strip(); row.display_priority=request.form.get("display_priority",0,type=int); success="تم تحديث الحملة."
                else: raise ValueError("إجراء الحملة غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=Campaign.query.filter_by(is_active=True).order_by(Campaign.id.desc()).limit(100).all()
        records=[{"id":x.id,"title":x.name,"badge":x.status,"edit_action":"update","archive_action":"archive","edit_fields":[{"name":"name","label":"اسم الحملة","required":True,"value":x.name},{"name":"slug","label":"Slug","dir":"ltr","value":x.slug},{"name":"status","label":"الحالة","type":"select","options":[{"value":"draft","label":"مسودة","selected":x.status=="draft"},{"value":"scheduled","label":"مجدولة","selected":x.status=="scheduled"},{"value":"active","label":"نشطة","selected":x.status=="active"}]},{"name":"display_priority","label":"الأولوية","type":"number","value":x.display_priority}],"fields":[{"label":"Slug","value":x.slug,"dir":"ltr"},{"label":"الأولوية","value":x.display_priority}]} for x in rows]
        return render_template("admin/manage.html",title="الحملات",section="المحتوى والمتجر",description="إضافة وتعديل وأرشفة الحملات، مع Slug تلقائي.",fields=[{"name":"name","label":"اسم الحملة","required":True},{"name":"slug","label":"Slug","dir":"ltr"},{"name":"status","label":"الحالة","type":"select","options":[{"value":"draft","label":"مسودة","selected":True},{"value":"scheduled","label":"مجدولة"},{"value":"active","label":"نشطة"}]},{"name":"display_priority","label":"الأولوية","type":"number","value":0}],records=records,modal_id="campaignAddModal",success=success,error=error,**context)


    @admin_bp.route("/hashtags", methods=["GET", "POST"])
    def hashtags():
        from .entity_views import _unique_slug
        context=_ctx(); error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(Hashtag,request.form.get("id",type=int))
                if action=="create":
                    name=(request.form.get("name") or "").strip(); display=(request.form.get("display_name") or "").strip() or name
                    if not name: raise ValueError("اسم الوسم مطلوب.")
                    slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Hashtag,display,fallback="tag")
                    if Hashtag.query.filter_by(slug=slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    db.session.add(Hashtag(name=name,slug=slug,display_name=display,sort_order=request.form.get("sort_order",0,type=int))); success="تم إنشاء الوسم."
                elif row is None: raise ValueError("الوسم غير موجود.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة الوسم."
                elif action=="update":
                    name=(request.form.get("name") or "").strip(); display=(request.form.get("display_name") or "").strip() or name; slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Hashtag,display,exclude_id=row.id,fallback="tag")
                    if not name: raise ValueError("اسم الوسم مطلوب.")
                    if Hashtag.query.filter(Hashtag.id!=row.id,Hashtag.slug==slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    row.name=name; row.display_name=display; row.slug=slug; row.sort_order=request.form.get("sort_order",0,type=int); success="تم تحديث الوسم."
                else: raise ValueError("إجراء الوسم غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=Hashtag.query.filter_by(is_active=True).order_by(Hashtag.sort_order,Hashtag.id.desc()).limit(300).all()
        records=[{"id":x.id,"title":x.display_name or x.name,"badge":f"#{x.id}","edit_action":"update","archive_action":"archive","edit_fields":[{"name":"name","label":"الاسم","required":True,"value":x.name},{"name":"slug","label":"Slug","dir":"ltr","value":x.slug},{"name":"display_name","label":"اسم العرض","value":x.display_name or x.name},{"name":"sort_order","label":"الترتيب","type":"number","value":x.sort_order}],"fields":[{"label":"Slug","value":x.slug,"dir":"ltr"},{"label":"الترتيب","value":x.sort_order}]} for x in rows]
        return render_template("admin/manage.html",title="الهاشتاجات",section="المحتوى والمتجر",description="إضافة وتعديل وأرشفة الهاشتاجات مع Slug تلقائي.",fields=[{"name":"name","label":"الاسم","required":True},{"name":"slug","label":"Slug","dir":"ltr"},{"name":"display_name","label":"اسم العرض"},{"name":"sort_order","label":"الترتيب","type":"number","value":0}],records=records,modal_id="hashtagAddModal",success=success,error=error,**context)



def _ctx():
    return build_admin_context()
