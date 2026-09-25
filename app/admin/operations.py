from decimal import Decimal, InvalidOperation

from flask import render_template, request

from ..extensions import db
from ..models import (
    Banner,
    Campaign,
    Currency,
    PricingGroup,
    PricingGroupRule,
    Hashtag,
)
from ..services.pricing import PricingRule, calculate_customer_price
from .context import build_admin_context


def register_operation_routes(admin_bp):
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
            name = (request.form.get("name") or "").strip()
            asset_id = request.form.get("image_asset_id", type=int)
            if not name or not asset_id:
                error = "اسم البانر وAsset للصورة مطلوبان."
            else:
                db.session.add(Banner(
                    name=name,
                    image_asset_id=asset_id,
                    mobile_asset_id=request.form.get("mobile_asset_id", type=int),
                    size_spec=(request.form.get("size_spec") or "").strip() or None,
                    overlay_text=(request.form.get("overlay_text") or "").strip() or None,
                    position_text=(request.form.get("position_text") or "").strip() or None,
                    status="draft",
                ))
                db.session.commit()
                success = "تم إنشاء البانر كمسودة."
        rows = Banner.query.order_by(Banner.id.desc()).limit(100).all()
        return render_template("admin/banners.html", title="البانرات", banners=rows, success=success, error=error, **context)

    @admin_bp.route("/campaigns", methods=["GET", "POST"])
    def campaigns():
        context = _ctx()
        error = None
        success = None
        if request.method == "POST":
            name = (request.form.get("name") or "").strip()
            slug = (request.form.get("slug") or "").strip().lower()
            if not name or not slug:
                error = "اسم الحملة وSlug مطلوبان."
            else:
                db.session.add(Campaign(
                    name=name,
                    slug=slug,
                    start_at=None,
                    end_at=None,
                    status="draft",
                ))
                db.session.commit()
                success = "تم إنشاء الحملة كمسودة."
        rows = Campaign.query.order_by(Campaign.id.desc()).limit(100).all()
        return render_template("admin/campaigns.html", title="الحملات", campaigns=rows, success=success, error=error, **context)

    @admin_bp.route("/hashtags", methods=["GET", "POST"])
    def hashtags():
        context = _ctx()
        error = None
        success = None
        if request.method == "POST":
            name = (request.form.get("name") or "").strip()
            slug = (request.form.get("slug") or "").strip().lower()
            if not name or not slug:
                error = "اسم الوسم وSlug مطلوبان."
            else:
                db.session.add(Hashtag(name=name, slug=slug, display_name=request.form.get("display_name") or name))
                db.session.commit()
                success = "تم إنشاء الوسم."
        rows = Hashtag.query.order_by(Hashtag.sort_order, Hashtag.id.desc()).limit(200).all()
        return render_template("admin/hashtags.html", title="الهاشتاجات", hashtags=rows, success=success, error=error, **context)


def _ctx():
    return build_admin_context()
