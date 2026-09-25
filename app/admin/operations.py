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
                    if action.endsWith("_create"):
                        name=(request.form.get("name") or "").strip()
                        if not name: raise ValueError("اسم السياسة مطلوب.")
                        if kind == "shipping": row=ShippingPolicy(name=name, free_shipping_enabled=request.form.get("free_shipping_enabled")=="on", min_order_amount=request.form.get("min_order_amount") or None, promo_text=request.form.get("promo_text") or None, delivery_window=request.form.get("delivery_window") or None)
                        elif kind == "return": row=ReturnPolicy(name=name, return_window_days=request.form.get("return_window_days",0,type=int), conditions=request.form.get("conditions") or None, fee_rule=request.form.get("fee_rule") or None, refund_method=request.form.get("refund_method") or None)
                        else: row=WarrantyPolicy(name=name, duration_days=request.form.get("duration_days",0,type=int), coverage=request.form.get("coverage") or None, exclusions=request.form.get("exclusions") or None, claim_method=request.form.get("claim_method") or None)
                        db.session.add(row); success="تمت إضافة السياسة."
                    elif row is None: raise ValueError("السياسة غير موجودة.")
                    elif action.endsWith("_archive"): row.is_active=False; success="تمت أرشفة السياسة."
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

    @admin_bp.route("/pricing/groups", methods=["GET", "POST"])
    def pricing_groups():
        context = _ctx()
        error = None
        success = None

        if request.method == "POST":
            action = (request.form.get("action") or "create_group").strip()

            try:
                if action == "create_group":
                    name = (request.form.get("name") or "").strip()
                    default_currency_id = request.form.get("default_currency_id", type=int)
                    if not name or not default_currency_id:
                        raise ValueError("اسم المجموعة والعملة الافتراضية مطلوبان.")

                    group = PricingGroup(
                        name=name,
                        description=(request.form.get("description") or "").strip() or None,
                        default_currency_id=default_currency_id,
                        priority=request.form.get("priority", 0, type=int),
                        is_default=request.form.get("is_default") == "on",
                    )

                    if group.is_default and PricingGroup.query.filter_by(is_default=True, is_active=True).first():
                        raise ValueError("توجد مجموعة افتراضية فعالة بالفعل.")

                    db.session.add(group)
                    db.session.flush()

                    currency_ids = request.form.getlist("rule_currency_id")
                    percent_values = request.form.getlist("rule_percent_markup")
                    fixed_values = request.form.getlist("rule_fixed_markup")
                    decimals_values = request.form.getlist("rule_decimals")
                    rounding_values = request.form.getlist("rule_rounding_rule")

                    if not currency_ids:
                        currency_ids = [str(default_currency_id)]
                        percent_values = [request.form.get("percent_markup", "0")]
                        fixed_values = [request.form.get("fixed_markup", "0")]
                        decimals_values = [request.form.get("decimals", "2")]
                        rounding_values = [request.form.get("rounding_rule", "nearest")]

                    seen = set()
                    for index, raw_currency_id in enumerate(currency_ids):
                        currency_id = int(raw_currency_id)
                        if currency_id in seen:
                            raise ValueError("لا يمكن تكرار العملة داخل المجموعة.")
                        seen.add(currency_id)
                        if db.session.get(Currency, currency_id) is None:
                            raise ValueError("إحدى العملات المختارة غير موجودة.")

                        def _at(values, default):
                            return values[index] if index < len(values) and values[index] != "" else default

                        db.session.add(PricingGroupRule(
                            group_id=group.id,
                            currency_id=currency_id,
                            percent_markup=Decimal(_at(percent_values, "0")),
                            fixed_markup=Decimal(_at(fixed_values, "0")),
                            rounding_rule=_at(rounding_values, "nearest"),
                            decimals=int(_at(decimals_values, "2")),
                        ))

                    db.session.commit()
                    success = "تم إنشاء مجموعة التسعير وقواعد العملات."

                elif action == "assign_location":
                    group_id = request.form.get("location_group_id", type=int)
                    location_id = request.form.get("location_id", type=int)
                    scope = (request.form.get("location_scope") or "city").strip()
                    if not group_id or not location_id or scope not in {"city", "region"}:
                        raise ValueError("اختر المجموعة ونطاق الربط والمعرّف.")

                    if db.session.get(PricingGroup, group_id) is None:
                        raise ValueError("مجموعة التسعير غير موجودة.")

                    row = PricingGroupCity(
                        pricing_group_id=group_id,
                        city_id=location_id if scope == "city" else None,
                        region_id=location_id if scope == "region" else None,
                        priority=request.form.get("location_priority", 0, type=int),
                    )
                    db.session.add(row)
                    db.session.commit()
                    success = "تم ربط الموقع بمجموعة التسعير."

                elif action == "assign_customer":
                    customer_id = request.form.get("customer_id", type=int)
                    group_id = request.form.get("customer_group_id", type=int)
                    if not customer_id or not group_id:
                        raise ValueError("معرّف العميل ومجموعة التسعير مطلوبان.")
                    if db.session.get(Customer, customer_id) is None:
                        raise ValueError("العميل غير موجود.")
                    if db.session.get(PricingGroup, group_id) is None:
                        raise ValueError("مجموعة التسعير غير موجودة.")

                    percent_raw = (request.form.get("percent_override") or "").strip()
                    fixed_raw = (request.form.get("fixed_override") or "").strip()
                    db.session.add(CustomerPricingAssignment(
                        customer_id=customer_id,
                        pricing_group_id=group_id,
                        percent_override=Decimal(percent_raw) if percent_raw else None,
                        fixed_override=Decimal(fixed_raw) if fixed_raw else None,
                        priority=request.form.get("customer_priority", 0, type=int),
                    ))
                    db.session.commit()
                    success = "تم تعيين مجموعة التسعير للعميل."

                else:
                    raise ValueError("إجراء التسعير غير معروف.")

            except (ValueError, InvalidOperation) as exc:
                db.session.rollback()
                error = str(exc)

        groups = PricingGroup.query.filter_by(is_active=True).order_by(
            PricingGroup.priority.desc(), PricingGroup.id.desc()
        ).all()
        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        regions = Region.query.filter_by(is_active=True).order_by(Region.sort_order, Region.name).all()
        cities = City.query.filter_by(is_active=True).order_by(City.sort_order, City.name).all()
        customers = Customer.query.filter_by(is_active=True).order_by(Customer.id.desc()).limit(200).all()
        rules = PricingGroupRule.query.order_by(PricingGroupRule.group_id, PricingGroupRule.id).all()
        location_assignments = PricingGroupCity.query.filter_by(is_active=True).order_by(
            PricingGroupCity.priority.desc(), PricingGroupCity.id.desc()
        ).limit(200).all()
        customer_assignments = CustomerPricingAssignment.query.filter_by(is_active=True).order_by(
            CustomerPricingAssignment.priority.desc(), CustomerPricingAssignment.id.desc()
        ).limit(200).all()

        currency_map = {row.id: row for row in currencies}
        group_map = {row.id: row for row in groups}
        city_map = {row.id: row for row in cities}
        region_map = {row.id: row for row in regions}
        customer_map = {row.id: row for row in customers}

        return render_template(
            "admin/pricing_groups.html",
            title="مجموعات التسعير",
            groups=groups,
            currencies=currencies,
            regions=regions,
            cities=cities,
            customers=customers,
            rules=rules,
            location_assignments=location_assignments,
            customer_assignments=customer_assignments,
            currency_map=currency_map,
            group_map=group_map,
            city_map=city_map,
            region_map=region_map,
            customer_map=customer_map,
            success=success,
            error=error,
            **context,
        )

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

        if request.method == "POST":
            action = (request.form.get("action") or "create_banner").strip()
            try:
                if action == "create_banner":
                    name = (request.form.get("name") or "").strip()
                    image_file = request.files.get("image_file")
                    mobile_file = request.files.get("mobile_image_file")

                    if not name or not image_file or not image_file.filename:
                        raise ValueError("اسم البانر والصورة الأساسية مطلوبان.")

                    upload_files = [image_file]
                    if mobile_file and mobile_file.filename:
                        upload_files.append(mobile_file)

                    assets = MediaService.save_generic_files(upload_files, "banners")
                    if not assets:
                        raise ValueError("تعذر رفع الصورة.")

                    banner = Banner(
                        name=name,
                        image_asset_id=assets[0]["id"],
                        mobile_asset_id=assets[1]["id"] if len(assets) > 1 else None,
                        size_spec=(request.form.get("size_spec") or "").strip() or None,
                        overlay_text=(request.form.get("overlay_text") or "").strip() or None,
                        position_text=(request.form.get("position_text") or "").strip() or None,
                        duration=request.form.get("duration", type=int),
                        status="draft",
                    )
                    db.session.add(banner)
                    db.session.commit()
                    success = "تم رفع صور البانر وإنشاء المسودة."

                elif action == "add_target":
                    banner_id = request.form.get("banner_id", type=int)
                    target_type = (request.form.get("target_type") or "").strip()
                    target_id = request.form.get("target_id", type=int)
                    url = (request.form.get("target_url") or "").strip() or None

                    if db.session.get(Banner, banner_id) is None:
                        raise ValueError("البانر غير موجود.")
                    if target_type not in {"category", "product", "campaign", "url"}:
                        raise ValueError("نوع الهدف غير مدعوم.")

                    if target_type == "url":
                        if not url:
                            raise ValueError("الرابط مطلوب.")
                        target_id = None
                    else:
                        if not target_id:
                            raise ValueError("معرّف الهدف مطلوب.")
                        model = {
                            "category": Category,
                            "product": Product,
                            "campaign": Campaign,
                        }[target_type]
                        if db.session.get(model, target_id) is None:
                            raise ValueError("الهدف المختار غير موجود.")
                        url = None

                    db.session.add(BannerTarget(
                        banner_id=banner_id,
                        target_type=target_type,
                        target_id=target_id,
                        url=url,
                        priority=request.form.get("target_priority", 0, type=int),
                    ))
                    db.session.commit()
                    success = "تم ربط هدف البانر."

                else:
                    raise ValueError("إجراء البانر غير معروف.")

            except (ValueError, OSError) as exc:
                db.session.rollback()
                error = str(exc)

        banners = Banner.query.order_by(Banner.id.desc()).limit(100).all()
        banner_ids = [row.id for row in banners]
        asset_ids = []
        for row in banners:
            asset_ids.extend([row.image_asset_id, row.mobile_asset_id] if row.mobile_asset_id else [row.image_asset_id])
        assets = MediaAsset.query.filter(MediaAsset.id.in_(asset_ids)).all() if asset_ids else []
        asset_map = {asset.id: asset for asset in assets}
        targets = (
            BannerTarget.query
            .filter(BannerTarget.banner_id.in_(banner_ids))
            .order_by(BannerTarget.priority.desc(), BannerTarget.id.desc())
            .all()
            if banner_ids else []
        )
        categories = Category.query.filter_by(is_active=True).order_by(Category.sort_order, Category.name).limit(300).all()
        products = Product.query.filter(Product.is_active.is_(True), Product.status != "archived").order_by(Product.id.desc()).limit(300).all()
        campaigns = Campaign.query.filter_by(is_active=True).order_by(Campaign.display_priority.desc(), Campaign.name).limit(200).all()

        return render_template(
            "admin/banners.html",
            title="البانرات",
            banners=banners,
            asset_map=asset_map,
            targets=targets,
            categories=categories,
            products=products,
            campaigns=campaigns,
            success=success,
            error=error,
            **context,
        )

    @admin_bp.route("/campaigns", methods=["GET", "POST"])
    def campaigns():
        from .entity_views import _unique_slug
        context = _ctx()
        error = None
        success = None
        if request.method == "POST":
            try:
                name = (request.form.get("name") or "").strip()
                if not name:
                    raise ValueError("اسم الحملة مطلوب.")
                slug = (request.form.get("slug") or "").strip().lower() or _unique_slug(Campaign, name, fallback="campaign")
                if Campaign.query.filter_by(slug=slug).first():
                    raise ValueError("الـSlug مستخدم مسبقًا.")
                db.session.add(Campaign(
                    name=name,
                    slug=slug,
                    start_at=None,
                    end_at=None,
                    status=(request.form.get("status") or "draft").strip(),
                    display_priority=request.form.get("display_priority", 0, type=int),
                ))
                db.session.commit()
                success = "تم إنشاء الحملة كمسودة."
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)
        rows = Campaign.query.order_by(Campaign.id.desc()).limit(100).all()
        records = [{
            "title": row.name,
            "badge": row.status,
            "fields": [
                {"label": "Slug", "value": row.slug, "dir": "ltr"},
                {"label": "الأولوية", "value": row.display_priority},
            ],
        } for row in rows]
        return render_template(
            "admin/manage.html", title="الحملات", section="المحتوى والمتجر",
            description="أنشئ الحملة من الزر، والـSlug يُولد تلقائيًا ويمكن تعديله.",
            fields=[
                {"name": "name", "label": "اسم الحملة", "required": True, "placeholder": "مثال: تخفيضات الخريف"},
                {"name": "slug", "label": "Slug", "dir": "ltr", "placeholder": "يُولد تلقائيًا"},
                {"name": "status", "label": "الحالة", "type": "select", "options": [
                    {"value": "draft", "label": "مسودة", "selected": True},
                    {"value": "scheduled", "label": "مجدولة"},
                    {"value": "active", "label": "نشطة"},
                ]},
                {"name": "display_priority", "label": "الأولوية", "type": "number", "value": 0, "min": 0},
            ],
            records=records, modal_id="campaignAddModal", success=success, error=error, **context,
        )

    @admin_bp.route("/hashtags", methods=["GET", "POST"])
    def hashtags():
        from .entity_views import _unique_slug
        context = _ctx()
        error = None
        success = None
        if request.method == "POST":
            try:
                name = (request.form.get("name") or "").strip()
                if not name:
                    raise ValueError("اسم الوسم مطلوب.")
                display_name = (request.form.get("display_name") or "").strip() or name
                slug = (request.form.get("slug") or "").strip().lower() or _unique_slug(Hashtag, display_name, fallback="tag")
                if Hashtag.query.filter_by(slug=slug).first():
                    raise ValueError("الـSlug مستخدم مسبقًا.")
                db.session.add(Hashtag(name=name, slug=slug, display_name=display_name,
                                       sort_order=request.form.get("sort_order", 0, type=int)))
                db.session.commit()
                success = "تم إنشاء الوسم."
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)
        rows = Hashtag.query.order_by(Hashtag.sort_order, Hashtag.id.desc()).limit(200).all()
        records = [{
            "title": row.display_name or row.name,
            "badge": f"#{row.id}",
            "fields": [
                {"label": "Slug", "value": row.slug, "dir": "ltr"},
                {"label": "الاسم الداخلي", "value": row.name},
                {"label": "الترتيب", "value": row.sort_order},
            ],
        } for row in rows]
        return render_template(
            "admin/manage.html", title="الهاشتاجات", section="المحتوى والمتجر",
            description="قائمة الهاشتاجات أولًا، والإضافة من نافذة مستقلة مع Slug تلقائي.",
            fields=[
                {"name": "name", "label": "الاسم", "required": True, "placeholder": "مثال: عروض_العيد"},
                {"name": "slug", "label": "Slug", "dir": "ltr", "placeholder": "يُولد تلقائيًا"},
                {"name": "display_name", "label": "اسم العرض", "placeholder": "#عروض_العيد"},
                {"name": "sort_order", "label": "الترتيب", "type": "number", "value": 0, "min": 0},
            ],
            records=records, modal_id="hashtagLegacyAddModal", success=success, error=error, **context,
        )


def _ctx():
    return build_admin_context()
