from decimal import Decimal, InvalidOperation

from flask import render_template, request

from sqlalchemy.exc import IntegrityError

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
                    db.session.commit()
                    success = "تم إنشاء مجموعة التسعير. الآن اربطها بمدينة أو منطقة."

                elif action == "update":
                    if row is None:
                        raise ValueError("مجموعة التسعير غير موجودة.")
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
                    db.session.commit()
                    success = "تم تحديث مجموعة التسعير."

                elif action == "archive":
                    if row is None:
                        raise ValueError("مجموعة التسعير غير موجودة.")
                    row.is_active = False
                    if row.is_default:
                        row.is_default = False
                    db.session.commit()
                    success = "تمت أرشفة مجموعة التسعير."

                elif action == "assign_location":
                    group_id = request.form.get("pricing_group_id", type=int)
                    scope = (request.form.get("location_scope") or "city").strip()
                    location_id = request.form.get("location_id", type=int)
                    group = db.session.get(PricingGroup, group_id)
                    if group is None or not group.is_active:
                        raise ValueError("مجموعة التسعير غير موجودة.")
                    if scope not in {"region", "city", "area"} or not location_id:
                        raise ValueError("اختر التطبيق حسب المحافظة أو المدينة أو المنطقة داخل المدينة.")
                    region_id = location_id if scope == "region" else None
                    city_id = location_id if scope == "city" else None
                    area_id = location_id if scope == "area" else None
                    target = (
                        db.session.get(Region, region_id)
                        if region_id else
                        db.session.get(City, city_id)
                        if city_id else
                        db.session.get(CityArea, area_id)
                    )
                    if target is None or not target.is_active:
                        raise ValueError("الموقع المختار غير موجود أو غير فعال.")
                    query = PricingGroupCity.query.filter_by(pricing_group_id=group_id, is_active=True)
                    if region_id:
                        query = query.filter(PricingGroupCity.region_id == region_id)
                    elif city_id:
                        query = query.filter(PricingGroupCity.city_id == city_id)
                    else:
                        query = query.filter(PricingGroupCity.area_id == area_id)
                    if query.first():
                        raise ValueError("هذا الموقع مرتبط بالفعل بهذه المجموعة.")
                    db.session.add(PricingGroupCity(
                        pricing_group_id=group_id,
                        region_id=region_id,
                        city_id=city_id,
                        area_id=area_id,
                        priority=request.form.get("location_priority", 0, type=int) or 0,
                    ))
                    db.session.commit()
                    success = "تم تطبيق مجموعة التسعير على الموقع."

                elif action == "archive_assignment":
                    assignment = db.session.get(PricingGroupCity, request.form.get("assignment_id", type=int))
                    if assignment is None:
                        raise ValueError("ربط الموقع غير موجود.")
                    assignment.is_active = False
                    db.session.commit()
                    success = "تم إلغاء تطبيق المجموعة على هذا الموقع."
                else:
                    raise ValueError("إجراء مجموعة التسعير غير معروف.")
            except (ValueError, TypeError, IntegrityError) as exc:
                db.session.rollback()
                error = "تعذر حفظ التغيير: " + str(exc)

        groups = PricingGroup.query.order_by(
            PricingGroup.is_active.desc(),
            PricingGroup.priority.desc(),
            PricingGroup.name,
        ).limit(200).all()
        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        location_rows = PricingGroupCity.query.filter_by(is_active=True).order_by(
            PricingGroupCity.priority.desc(), PricingGroupCity.id.desc()
        ).limit(500).all()
        regions = Region.query.filter_by(is_active=True).order_by(Region.name).all()
        cities = City.query.filter_by(is_active=True).order_by(City.name).all()
        areas = CityArea.query.filter_by(is_active=True).order_by(CityArea.name).all()
        region_map = {x.id: x.name for x in regions}
        city_map = {x.id: x.name for x in cities}
        area_map = {x.id: x.name for x in areas}
        assignments = {group.id: sum(1 for item in location_rows if item.pricing_group_id == group.id) for group in groups}
        return render_template(
            "admin/pricing_groups_clear.html",
            title="مجموعات التسعير",
            section="التسعير",
            groups=groups,
            currencies=currencies,
            regions=regions,
            cities=cities,
            areas=areas,
            location_rows=location_rows,
            region_map=region_map,
            city_map=city_map,
            area_map=area_map,
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

    @admin_bp.route("/pricing/customer-overrides", methods=["GET", "POST"])
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
                    if Country.query.filter(Country.code == code).first():
                        raise ValueError("كود الدولة مستخدم بالفعل.")
                    db.session.add(Country(
                        code=code,
                        name_ar=name,
                        name_en=(request.form.get("name_en") or "").strip() or None,
                        phone_code=(request.form.get("phone_code") or "").strip() or None,
                    ))
                    db.session.commit()
                    success = "تمت إضافة الدولة."

                elif action == "region":
                    country_id = request.form.get("country_id", type=int)
                    code = (request.form.get("code") or "").strip().upper()
                    name = (request.form.get("name") or "").strip()
                    country = db.session.get(Country, country_id)
                    if country is None or not country.is_active:
                        raise ValueError("اختر الدولة أولًا.")
                    if not code or not name:
                        raise ValueError("كود المحافظة/المنطقة واسمها مطلوبان.")
                    if Region.query.filter(Region.country_id == country_id, Region.code == code).first():
                        raise ValueError("كود المحافظة/المنطقة مستخدم داخل الدولة.")
                    db.session.add(Region(
                        country_id=country_id, code=code, name=name,
                        sort_order=request.form.get("sort_order", 0, type=int) or 0,
                    ))
                    db.session.commit()
                    success = "تمت إضافة المحافظة/المنطقة."

                elif action == "city":
                    region_id = request.form.get("region_id", type=int)
                    code = (request.form.get("code") or "").strip().upper()
                    name = (request.form.get("name") or "").strip()
                    region = db.session.get(Region, region_id)
                    if region is None or not region.is_active:
                        raise ValueError("اختر المحافظة/المنطقة أولًا.")
                    if not code or not name:
                        raise ValueError("كود المدينة واسمها مطلوبان.")
                    if City.query.filter(City.region_id == region_id, City.code == code).first():
                        raise ValueError("كود المدينة مستخدم داخل هذه المحافظة/المنطقة.")
                    db.session.add(City(
                        region_id=region_id, code=code, name=name,
                        direction=(request.form.get("direction") or "").strip() or None,
                        source=(request.form.get("source") or "").strip() or None,
                        sort_order=request.form.get("sort_order", 0, type=int) or 0,
                    ))
                    db.session.commit()
                    success = "تمت إضافة المدينة."

                elif action == "area":
                    city_id = request.form.get("city_id", type=int)
                    code = (request.form.get("code") or "").strip().upper()
                    name = (request.form.get("name") or "").strip()
                    city = db.session.get(City, city_id)
                    if city is None or not city.is_active:
                        raise ValueError("اختر المدينة أولًا.")
                    if not code or not name:
                        raise ValueError("كود المنطقة داخل المدينة واسمها مطلوبان.")
                    if CityArea.query.filter(CityArea.city_id == city_id, CityArea.code == code).first():
                        raise ValueError("كود المنطقة داخل المدينة مستخدم.")
                    db.session.add(CityArea(
                        city_id=city_id, code=code, name=name,
                        direction=(request.form.get("direction") or "").strip() or None,
                        source=(request.form.get("source") or "").strip() or None,
                        sort_order=request.form.get("sort_order", 0, type=int) or 0,
                    ))
                    db.session.commit()
                    success = "تمت إضافة المنطقة داخل المدينة."
                else:
                    raise ValueError("إجراء المواقع غير معروف.")
            except (ValueError, TypeError, IntegrityError) as exc:
                db.session.rollback()
                error = "تعذر حفظ الموقع: " + str(exc)

        countries = Country.query.filter_by(is_active=True).order_by(Country.name_ar).all()
        regions = Region.query.filter_by(is_active=True).order_by(Region.name).limit(1000).all()
        cities = City.query.filter_by(is_active=True).order_by(City.name).limit(1000).all()
        areas = CityArea.query.filter_by(is_active=True).order_by(CityArea.name).limit(3000).all()
        regions_by_country = {}
        cities_by_region = {}
        areas_by_city = {}
        for item in regions:
            regions_by_country.setdefault(item.country_id, []).append(item)
        for item in cities:
            cities_by_region.setdefault(item.region_id, []).append(item)
        for item in areas:
            areas_by_city.setdefault(item.city_id, []).append(item)
        return render_template(
            "admin/geo_management_clear.html",
            title="المدن والمناطق",
            section="التسعير",
            countries=countries,
            regions=regions,
            cities=cities,
            areas=areas,
            regions_by_country=regions_by_country,
            cities_by_region=cities_by_region,
            areas_by_city=areas_by_city,
            country_map={x.id: x.name_ar for x in countries},
            region_map={x.id: x.name for x in regions},
            city_map={x.id: x.name for x in cities},
            directions=DIRECTIONS,
            direction_map=dict(DIRECTIONS),
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
                action = (request.form.get("action") or "").strip()
                row = db.session.get(ShippingRate, request.form.get("id", type=int))

                if action == "method":
                    name = (request.form.get("name") or "").strip()
                    code = (request.form.get("code") or "").strip().lower()
                    lo = request.form.get("delivery_days_min", type=int)
                    hi = request.form.get("delivery_days_max", type=int)
                    if not name or not code:
                        raise ValueError("اسم طريقة التوصيل والكود مطلوبان.")
                    if lo is not None and hi is not None and hi < lo:
                        raise ValueError("المدة القصوى لا يمكن أن تكون أقل من الدنيا.")
                    if ShippingMethod.query.filter(ShippingMethod.code == code).first():
                        raise ValueError("كود طريقة التوصيل مستخدم بالفعل.")
                    db.session.add(ShippingMethod(
                        name=name, code=code,
                        delivery_days_min=lo, delivery_days_max=hi,
                        supports_cod=request.form.get("supports_cod") == "on",
                    ))
                    db.session.commit()
                    success = "تمت إضافة طريقة التوصيل."

                elif action == "method_update":
                    method = db.session.get(ShippingMethod, request.form.get("method_id", type=int))
                    if method is None:
                        raise ValueError("طريقة التوصيل غير موجودة.")
                    name = (request.form.get("name") or "").strip()
                    code = (request.form.get("code") or "").strip().lower()
                    lo = request.form.get("delivery_days_min", type=int)
                    hi = request.form.get("delivery_days_max", type=int)
                    if not name or not code:
                        raise ValueError("اسم طريقة التوصيل والكود مطلوبان.")
                    if lo is not None and hi is not None and hi < lo:
                        raise ValueError("المدة القصوى لا يمكن أن تكون أقل من الدنيا.")
                    if ShippingMethod.query.filter(
                        ShippingMethod.id != method.id, ShippingMethod.code == code
                    ).first():
                        raise ValueError("كود طريقة التوصيل مستخدم بالفعل.")
                    method.name = name
                    method.code = code
                    method.delivery_days_min = lo
                    method.delivery_days_max = hi
                    method.supports_cod = request.form.get("supports_cod") == "on"
                    db.session.commit()
                    success = "تم تحديث طريقة التوصيل."

                elif action == "method_archive":
                    method = db.session.get(ShippingMethod, request.form.get("method_id", type=int))
                    if method is None:
                        raise ValueError("طريقة التوصيل غير موجودة.")
                    method.is_active = False
                    db.session.commit()
                    success = "تمت أرشفة طريقة التوصيل."

                elif action in {"create", "update"}:
                    method_id = request.form.get("method_id", type=int)
                    if db.session.get(ShippingMethod, method_id) is None:
                        raise ValueError("اختر طريقة التوصيل أولًا.")
                    scope = (request.form.get("location_scope") or "global").strip()
                    customer_id = request.form.get("customer_id", type=int) or None
                    region_id = request.form.get("region_id", type=int) or None
                    city_id = request.form.get("city_id", type=int) or None
                    area_id = request.form.get("city_area_id", type=int) or None

                    if scope == "global":
                        customer_id = region_id = city_id = area_id = None
                    elif scope == "customer":
                        if not customer_id or db.session.get(Customer, customer_id) is None:
                            raise ValueError("اختر عميلًا صحيحًا.")
                        region_id = city_id = area_id = None
                    elif scope == "region":
                        if not region_id or db.session.get(Region, region_id) is None:
                            raise ValueError("اختر محافظة/منطقة صحيحة.")
                        customer_id = city_id = area_id = None
                    elif scope == "city":
                        if not city_id or db.session.get(City, city_id) is None:
                            raise ValueError("اختر مدينة صحيحة.")
                        customer_id = region_id = area_id = None
                    elif scope == "area":
                        area = db.session.get(CityArea, area_id)
                        if area is None or not area.is_active:
                            raise ValueError("اختر منطقة صحيحة داخل المدينة.")
                        customer_id = region_id = city_id = None
                    else:
                        raise ValueError("نطاق القاعدة غير معروف.")

                    min_sar = _decimal(request.form.get("min_order_sar"), "0") if request.form.get("min_order_sar") else None
                    max_sar = _decimal(request.form.get("max_order_sar"), "0") if request.form.get("max_order_sar") else None
                    price_sar = _decimal(request.form.get("price_sar"), "0")
                    free_over = _decimal(request.form.get("free_over_sar"), "0") if request.form.get("free_over_sar") else None
                    if price_sar < 0:
                        raise ValueError("سعر التوصيل لا يمكن أن يكون سالبًا.")
                    if min_sar is not None and max_sar is not None and max_sar < min_sar:
                        raise ValueError("الحد الأعلى للسلة يجب ألا يقل عن الحد الأدنى.")

                    payload = dict(
                        method_id=method_id, customer_id=customer_id,
                        region_id=region_id, city_id=city_id, city_area_id=area_id,
                        min_order_sar=min_sar, max_order_sar=max_sar,
                        price_sar=price_sar, free_over_sar=free_over,
                        priority=request.form.get("priority", 0, type=int) or 0,
                        price=price_sar, min_order=min_sar,
                        max_order=max_sar, free_over=free_over,
                    )
                    if action == "create":
                        db.session.add(ShippingRate(**payload))
                        success = "تمت إضافة قاعدة التوصيل."
                    else:
                        if row is None:
                            raise ValueError("قاعدة التوصيل غير موجودة.")
                        for key, value in payload.items():
                            setattr(row, key, value)
                        success = "تم تحديث قاعدة التوصيل."
                    db.session.commit()

                elif action == "archive":
                    if row is None:
                        raise ValueError("قاعدة التوصيل غير موجودة.")
                    row.is_active = False
                    db.session.commit()
                    success = "تمت أرشفة قاعدة التوصيل."
                else:
                    raise ValueError("إجراء التوصيل غير معروف.")
            except (ValueError, TypeError, IntegrityError) as exc:
                db.session.rollback()
                error = "تعذر حفظ إعداد التوصيل: " + str(exc)

        methods = ShippingMethod.query.filter_by(is_active=True).order_by(ShippingMethod.name).all()
        customers = Customer.query.filter_by(is_active=True).order_by(Customer.id.desc()).limit(500).all()
        regions = Region.query.filter_by(is_active=True).order_by(Region.name).all()
        cities = City.query.filter_by(is_active=True).order_by(City.name).all()
        areas = CityArea.query.filter_by(is_active=True).order_by(CityArea.name).all()
        rows = ShippingRate.query.filter_by(is_active=True).order_by(
            ShippingRate.priority.desc(), ShippingRate.id.desc()
        ).limit(500).all()
        return render_template(
            "admin/shipping_rates_clear.html",
            title="طرق التوصيل وقواعدها",
            section="المبيعات والطلبات",
            methods=methods,
            customers=customers,
            regions=regions,
            cities=cities,
            areas=areas,
            rows=rows,
            region_map={x.id: x.name for x in regions},
            city_map={x.id: x.name for x in cities},
            area_map={x.id: x.name for x in areas},
            method_map={x.id: x.name for x in methods},
            customer_map={x.id: (x.name or x.phone_normalized) for x in customers},
            error=error,
            success=success,
            **build_admin_context(),
        )

