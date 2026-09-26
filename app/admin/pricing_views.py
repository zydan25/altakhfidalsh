from decimal import Decimal, InvalidOperation

from flask import render_template, request

from ..extensions import db
from ..models import (
    City,
    CityArea,
    Country,
    Currency,
    Customer,
    CustomerPricingAssignment,
    ExchangeRate,
    PricingGroup,
    PricingGroupCity,
    Region,
    ShippingMethod,
    ShippingRate,
)
from .context import build_admin_context


DIRECTIONS = (
    ("", "بدون اتجاه"),
    ("north", "شمال"),
    ("south", "جنوب"),
    ("east", "شرق"),
    ("west", "غرب"),
    ("center", "وسط"),
)


def _decimal(raw, default="0"):
    try:
        return Decimal(str(raw if raw not in (None, "") else default))
    except (InvalidOperation, ValueError):
        raise ValueError("القيمة المالية غير صحيحة.")


def register_pricing_views(admin_bp):
    @admin_bp.route("/pricing/groups", methods=["GET", "POST"])
    def pricing_groups():
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "create").strip()
                row = db.session.get(PricingGroup, request.form.get("id", type=int))
                if action == "create":
                    name = (request.form.get("name") or "").strip()
                    if not name:
                        raise ValueError("اسم مجموعة التسعير مطلوب.")
                    group = PricingGroup(
                        name=name,
                        description=(request.form.get("description") or "").strip() or None,
                        default_currency_id=request.form.get("default_currency_id", type=int) or None,
                        percent_markup=_decimal(request.form.get("percent_markup")),
                        fixed_markup_sar=_decimal(request.form.get("fixed_markup_sar")),
                        rounding_rule=(request.form.get("rounding_rule") or "nearest").strip(),
                        decimals=max(0, min(6, request.form.get("decimals", 2, type=int))),
                        priority=request.form.get("priority", 0, type=int) or 0,
                        is_default=request.form.get("is_default") == "on",
                    )
                    if group.percent_markup < 0 or group.fixed_markup_sar < 0:
                        raise ValueError("الزيادة لا يمكن أن تكون سالبة.")
                    if group.is_default and PricingGroup.query.filter_by(is_default=True, is_active=True).first():
                        raise ValueError("توجد مجموعة افتراضية فعالة بالفعل.")
                    db.session.add(group)
                    success = "تم إنشاء مجموعة التسعير."
                elif row is None:
                    raise ValueError("مجموعة التسعير غير موجودة.")
                elif action == "update":
                    name = (request.form.get("name") or "").strip()
                    if not name:
                        raise ValueError("اسم مجموعة التسعير مطلوب.")
                    is_default = request.form.get("is_default") == "on"
                    if is_default and PricingGroup.query.filter(
                        PricingGroup.id != row.id,
                        PricingGroup.is_default.is_(True),
                        PricingGroup.is_active.is_(True),
                    ).first():
                        raise ValueError("توجد مجموعة افتراضية فعالة بالفعل.")
                    row.name = name
                    row.description = (request.form.get("description") or "").strip() or None
                    row.default_currency_id = request.form.get("default_currency_id", type=int) or None
                    row.percent_markup = _decimal(request.form.get("percent_markup"))
                    row.fixed_markup_sar = _decimal(request.form.get("fixed_markup_sar"))
                    row.rounding_rule = (request.form.get("rounding_rule") or "nearest").strip()
                    row.decimals = max(0, min(6, request.form.get("decimals", 2, type=int)))
                    row.priority = request.form.get("priority", 0, type=int) or 0
                    row.is_default = is_default
                    if row.percent_markup < 0 or row.fixed_markup_sar < 0:
                        raise ValueError("الزيادة لا يمكن أن تكون سالبة.")
                    success = "تم تحديث مجموعة التسعير."
                elif action == "archive":
                    row.is_active = False
                    if row.is_default:
                        row.is_default = False
                    success = "تمت أرشفة مجموعة التسعير."
                else:
                    raise ValueError("إجراء مجموعة التسعير غير معروف.")
                db.session.commit()
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        groups = PricingGroup.query.order_by(
            PricingGroup.is_active.desc(),
            PricingGroup.priority.desc(),
            PricingGroup.name,
        ).limit(200).all()
        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        assignments = {
            group.id: PricingGroupCity.query.filter_by(
                pricing_group_id=group.id, is_active=True
            ).count()
            for group in groups
        }
        return render_template(
            "admin/pricing_groups_clear.html",
            title="مجموعات التسعير",
            section="التسعير",
            groups=groups,
            currencies=currencies,
            assignments=assignments,
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.route("/pricing/exchange-rates", methods=["GET", "POST"])
    def exchange_rates():
        error = None
        success = None
        sar = Currency.query.filter(Currency.code == "SAR", Currency.is_active.is_(True)).first()
        if sar is None:
            error = "أنشئ العملة SAR أولًا قبل إضافة أسعار الصرف."

        if request.method == "POST":
            try:
                if sar is None:
                    raise ValueError("العملة الأساسية SAR غير موجودة.")
                action = (request.form.get("action") or "create").strip()
                row = db.session.get(ExchangeRate, request.form.get("id", type=int))
                quote_id = request.form.get("quote_currency_id", type=int)
                if action == "create":
                    quote = db.session.get(Currency, quote_id)
                    if quote is None or not quote.is_active or quote.code == "SAR":
                        raise ValueError("اختر عملة مستهدفة مختلفة عن SAR.")
                    rate = _decimal(request.form.get("rate"))
                    if rate <= 0:
                        raise ValueError("سعر الصرف يجب أن يكون أكبر من صفر.")
                    db.session.add(
                        ExchangeRate(
                            base_currency_id=sar.id,
                            quote_currency_id=quote.id,
                            rate=rate,
                            source=(request.form.get("source") or "").strip() or None,
                            valid_from=__import__("datetime").datetime.now(__import__("datetime").timezone.utc),
                        )
                    )
                    success = f"تم حفظ: 1 SAR = {rate} {quote.code}."
                elif row is None:
                    raise ValueError("سعر الصرف غير موجود.")
                elif action == "delete":
                    db.session.delete(row)
                    success = "تم حذف سعر الصرف."
                elif action == "update":
                    quote = db.session.get(Currency, quote_id)
                    if quote is None or not quote.is_active or quote.code == "SAR":
                        raise ValueError("اختر عملة مستهدفة مختلفة عن SAR.")
                    rate = _decimal(request.form.get("rate"))
                    if rate <= 0:
                        raise ValueError("سعر الصرف يجب أن يكون أكبر من صفر.")
                    row.base_currency_id = sar.id
                    row.quote_currency_id = quote.id
                    row.rate = rate
                    row.source = (request.form.get("source") or "").strip() or None
                    success = "تم تحديث سعر الصرف."
                else:
                    raise ValueError("إجراء سعر الصرف غير معروف.")
                db.session.commit()
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        rows = ExchangeRate.query.order_by(ExchangeRate.valid_from.desc(), ExchangeRate.id.desc()).limit(300).all()
        return render_template(
            "admin/exchange_rates_clear.html",
            title="أسعار الصرف",
            section="التسعير",
            sar=sar,
            currencies=currencies,
            rows=rows,
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.route("/pricing/location-assignments", methods=["GET", "POST"])
    def pricing_location_assignments():
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "create").strip()
                row = db.session.get(PricingGroupCity, request.form.get("id", type=int))
                if action == "create":
                    group_id = request.form.get("pricing_group_id", type=int)
                    city_id = request.form.get("city_id", type=int) or None
                    region_id = request.form.get("region_id", type=int) or None
                    area_id = request.form.get("area_id", type=int) or None
                    targets = [x for x in (city_id, region_id, area_id) if x is not None]
                    if len(targets) != 1:
                        raise ValueError("اختر موقعًا واحدًا فقط: مدينة أو منطقة أو جزء داخل المدينة.")
                    if db.session.get(PricingGroup, group_id) is None:
                        raise ValueError("مجموعة التسعير غير موجودة.")
                    if area_id and db.session.get(CityArea, area_id) is None:
                        raise ValueError("المنطقة داخل المدينة غير موجودة.")
                    db.session.add(
                        PricingGroupCity(
                            pricing_group_id=group_id,
                            city_id=city_id,
                            region_id=region_id,
                            area_id=area_id,
                            priority=request.form.get("priority", 0, type=int) or 0,
                        )
                    )
                    success = "تم ربط مجموعة التسعير بالموقع."
                elif row is None:
                    raise ValueError("الربط غير موجود.")
                elif action == "archive":
                    row.is_active = False
                    success = "تم إلغاء الربط."
                else:
                    raise ValueError("إجراء ربط التسعير غير معروف.")
                db.session.commit()
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        groups = PricingGroup.query.filter_by(is_active=True).order_by(PricingGroup.priority.desc(), PricingGroup.name).all()
        countries = Country.query.filter_by(is_active=True).order_by(Country.name_ar).all()
        regions = Region.query.filter_by(is_active=True).order_by(Region.name).all()
        cities = City.query.filter_by(is_active=True).order_by(City.name).all()
        areas = CityArea.query.filter_by(is_active=True).order_by(CityArea.name).all()
        rows = PricingGroupCity.query.filter_by(is_active=True).order_by(
            PricingGroupCity.priority.desc(), PricingGroupCity.id.desc()
        ).limit(300).all()
        group_map = {x.id: x.name for x in groups}
        region_map = {x.id: x.name for x in regions}
        city_map = {x.id: x.name for x in cities}
        area_map = {x.id: x.name for x in areas}
        return render_template(
            "admin/location_assignments_clear.html",
            title="تطبيق مجموعات التسعير",
            section="التسعير",
            groups=groups,
            countries=countries,
            regions=regions,
            cities=cities,
            areas=areas,
            rows=rows,
            group_map=group_map,
            region_map=region_map,
            city_map=city_map,
            area_map=area_map,
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.route("/pricing/customer-assignments", methods=["GET", "POST"])
    def pricing_customer_assignments():
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "create").strip()
                row = db.session.get(CustomerPricingAssignment, request.form.get("id", type=int))
                if action == "create":
                    customer_id = request.form.get("customer_id", type=int)
                    group_id = request.form.get("pricing_group_id", type=int)
                    if db.session.get(Customer, customer_id) is None or db.session.get(PricingGroup, group_id) is None:
                        raise ValueError("العميل أو مجموعة التسعير غير موجودة.")
                    db.session.add(
                        CustomerPricingAssignment(
                            customer_id=customer_id,
                            pricing_group_id=group_id,
                            percent_override=_decimal(request.form.get("percent_override")) if request.form.get("percent_override") else None,
                            fixed_override=_decimal(request.form.get("fixed_override_sar")) if request.form.get("fixed_override_sar") else None,
                            priority=request.form.get("priority", 0, type=int) or 0,
                        )
                    )
                    success = "تم إنشاء استثناء تسعيري للعميل."
                elif row is None:
                    raise ValueError("التعيين غير موجود.")
                elif action == "archive":
                    row.is_active = False
                    success = "تم إلغاء تعيين العميل."
                else:
                    raise ValueError("إجراء تعيين العميل غير معروف.")
                db.session.commit()
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        customers = Customer.query.filter_by(is_active=True).order_by(Customer.id.desc()).limit(300).all()
        groups = PricingGroup.query.filter_by(is_active=True).order_by(PricingGroup.priority.desc(), PricingGroup.name).all()
        rows = CustomerPricingAssignment.query.filter_by(is_active=True).order_by(
            CustomerPricingAssignment.priority.desc(), CustomerPricingAssignment.id.desc()
        ).limit(300).all()
        return render_template(
            "admin/customer_assignments_clear.html",
            title="استثناءات العملاء",
            section="التسعير",
            customers=customers,
            groups=groups,
            rows=rows,
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.route("/geo", methods=["GET", "POST"])
    def geo_management():
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "").strip()
                if action == "country":
                    code = (request.form.get("code") or "").strip().upper()
                    name = (request.form.get("name_ar") or "").strip()
                    if not code or not name:
                        raise ValueError("كود الدولة واسمها مطلوبان.")
                    db.session.add(
                        Country(
                            code=code,
                            name_ar=name,
                            name_en=(request.form.get("name_en") or "").strip() or None,
                            phone_code=(request.form.get("phone_code") or "").strip() or None,
                        )
                    )
                    success = "تمت إضافة الدولة."
                elif action == "region":
                    country_id = request.form.get("country_id", type=int)
                    if not country_id or db.session.get(Country, country_id) is None:
                        raise ValueError("اختر دولة صحيحة.")
                    db.session.add(
                        Region(
                            country_id=country_id,
                            code=(request.form.get("code") or "").strip().upper(),
                            name=(request.form.get("name") or "").strip(),
                            sort_order=request.form.get("sort_order", 0, type=int) or 0,
                        )
                    )
                    success = "تمت إضافة المنطقة/المحافظة."
                elif action == "city":
                    region_id = request.form.get("region_id", type=int)
                    if not region_id or db.session.get(Region, region_id) is None:
                        raise ValueError("اختر منطقة/محافظة صحيحة.")
                    db.session.add(
                        City(
                            region_id=region_id,
                            code=(request.form.get("code") or "").strip().upper(),
                            name=(request.form.get("name") or "").strip(),
                            direction=(request.form.get("direction") or "").strip() or None,
                            source=(request.form.get("source") or "").strip() or None,
                            sort_order=request.form.get("sort_order", 0, type=int) or 0,
                        )
                    )
                    success = "تمت إضافة المدينة."
                elif action == "area":
                    city_id = request.form.get("city_id", type=int)
                    if not city_id or db.session.get(City, city_id) is None:
                        raise ValueError("اختر مدينة صحيحة.")
                    db.session.add(
                        CityArea(
                            city_id=city_id,
                            code=(request.form.get("code") or "").strip().upper(),
                            name=(request.form.get("name") or "").strip(),
                            direction=(request.form.get("direction") or "").strip() or None,
                            source=(request.form.get("source") or "").strip() or None,
                            sort_order=request.form.get("sort_order", 0, type=int) or 0,
                        )
                    )
                    success = "تمت إضافة المنطقة الداخلية/الفرع."
                else:
                    raise ValueError("إجراء المواقع غير معروف.")
                db.session.commit()
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        countries = Country.query.filter_by(is_active=True).order_by(Country.name_ar).all()
        regions = Region.query.filter_by(is_active=True).order_by(Region.name).limit(500).all()
        cities = City.query.filter_by(is_active=True).order_by(City.name).limit(500).all()
        areas = CityArea.query.filter_by(is_active=True).order_by(CityArea.name).limit(1000).all()
        country_map = {x.id: x.name_ar for x in countries}
        region_map = {x.id: x.name for x in regions}
        city_map = {x.id: x.name for x in cities}
        return render_template(
            "admin/geo_management_clear.html",
            title="المدن والمناطق",
            section="التسعير",
            countries=countries,
            regions=regions,
            cities=cities,
            areas=areas,
            country_map=country_map,
            region_map=region_map,
            city_map=city_map,
            directions=DIRECTIONS,
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.route("/shipping/rates", methods=["GET", "POST"])
    def shipping_rates():
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "create").strip()
                row = db.session.get(ShippingRate, request.form.get("id", type=int))
                if action == "create":
                    method_id = request.form.get("method_id", type=int)
                    customer_id = request.form.get("customer_id", type=int) or None
                    region_id = request.form.get("region_id", type=int) or None
                    city_id = request.form.get("city_id", type=int) or None
                    area_id = request.form.get("city_area_id", type=int) or None
                    targets = [x for x in (region_id, city_id, area_id) if x is not None]
                    if len(targets) > 1:
                        raise ValueError("الموقع يكون منطقة أو مدينة أو جزءًا داخل المدينة، وليس أكثر من واحد.")
                    if db.session.get(ShippingMethod, method_id) is None:
                        raise ValueError("طريقة التوصيل غير موجودة.")
                    min_sar = _decimal(request.form.get("min_order_sar"), "0") if request.form.get("min_order_sar") else None
                    max_sar = _decimal(request.form.get("max_order_sar"), "0") if request.form.get("max_order_sar") else None
                    price_sar = _decimal(request.form.get("price_sar"), "0")
                    free_over = _decimal(request.form.get("free_over_sar"), "0") if request.form.get("free_over_sar") else None
                    if price_sar < 0 or (min_sar is not None and max_sar is not None and max_sar < min_sar):
                        raise ValueError("تحقق من السعر وحدود السلة.")
                    db.session.add(
                        ShippingRate(
                            method_id=method_id,
                            customer_id=customer_id,
                            region_id=region_id,
                            city_id=city_id,
                            city_area_id=area_id,
                            min_order_sar=min_sar,
                            max_order_sar=max_sar,
                            price_sar=price_sar,
                            free_over_sar=free_over,
                            priority=request.form.get("priority", 0, type=int) or 0,
                            price=price_sar,
                            min_order=min_sar,
                            max_order=max_sar,
                            free_over=free_over,
                        )
                    )
                    success = "تم إنشاء قاعدة سعر التوصيل."
                elif row is None:
                    raise ValueError("قاعدة التوصيل غير موجودة.")
                elif action == "archive":
                    row.is_active = False
                    success = "تم أرشفة قاعدة التوصيل."
                else:
                    raise ValueError("إجراء التوصيل غير معروف.")
                db.session.commit()
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        methods = ShippingMethod.query.filter_by(is_active=True).order_by(ShippingMethod.name).all()
        customers = Customer.query.filter_by(is_active=True).order_by(Customer.id.desc()).limit(300).all()
        regions = Region.query.filter_by(is_active=True).order_by(Region.name).all()
        cities = City.query.filter_by(is_active=True).order_by(City.name).all()
        areas = CityArea.query.filter_by(is_active=True).order_by(CityArea.name).all()
        rows = ShippingRate.query.filter_by(is_active=True).order_by(
            ShippingRate.priority.desc(), ShippingRate.id.desc()
        ).limit(300).all()
        region_map = {x.id: x.name for x in regions}
        city_map = {x.id: x.name for x in cities}
        area_map = {x.id: x.name for x in areas}
        method_map = {x.id: x.name for x in methods}
        customer_map = {x.id: (x.name or x.phone_normalized) for x in customers}
        return render_template(
            "admin/shipping_rates_clear.html",
            title="أسعار التوصيل",
            section="المبيعات والطلبات",
            methods=methods,
            customers=customers,
            regions=regions,
            cities=cities,
            areas=areas,
            rows=rows,
            region_map=region_map,
            city_map=city_map,
            area_map=area_map,
            method_map=method_map,
            customer_map=customer_map,
            error=error,
            success=success,
            **build_admin_context(),
        )
