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
            name = (request.form.get("name") or "").strip()
            currency_id = request.form.get("default_currency_id", type=int)
            if not name or not currency_id:
                error = "اسم المجموعة والعملة الافتراضية مطلوبان."
            else:
                group = PricingGroup(
                    name=name,
                    description=(request.form.get("description") or "").strip() or None,
                    default_currency_id=currency_id,
                    priority=int(request.form.get("priority", 0)),
                    is_default=bool(request.form.get("is_default")),
                )
                db.session.add(group)
                db.session.flush()
                db.session.add(PricingGroupRule(
                    group_id=group.id,
                    currency_id=currency_id,
                    percent_markup=Decimal(request.form.get("percent_markup", "0")),
                    fixed_markup=Decimal(request.form.get("fixed_markup", "0")),
                    rounding_rule=request.form.get("rounding_rule", "nearest"),
                    decimals=int(request.form.get("decimals", 2)),
                ))
                db.session.commit()
                success = "تم إنشاء مجموعة التسعير."

        groups = PricingGroup.query.order_by(PricingGroup.priority.desc(), PricingGroup.id.desc()).all()
        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        return render_template(
            "admin/pricing_groups.html",
            title="مجموعات التسعير",
            groups=groups,
            currencies=currencies,
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
