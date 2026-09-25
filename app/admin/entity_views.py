from flask import render_template, request, session

from ..extensions import db
from ..models import (
    AuditLog,
    Banner,
    Campaign,
    Conversation,
    Coupon,
    Customer,
    ExchangeRate,
    FeatureFlag,
    InventoryLocation,
    Order,
    PaymentMethod,
    PaymentTransaction,
    PricingGroup,
    PricingGroupCity,
    ProductDisplaySettings,
    ProductMedia,
    ProductVariant,
    Review,
    Role,
    ShippingMethod,
    ShippingPolicy,
    Theme,
    Wallet,
)
from .context import build_admin_context
from ..modules.commerce.services import CommerceService
from ..modules.support.services import SupportService


def _ctx():
    return build_admin_context()


def _render(title, columns, rows, section=None, actions=None):
    return render_template(
        "admin/entity_list.html",
        title=title,
        columns=columns,
        rows=rows,
        section=section or "الإدارة",
        actions=actions or [],
        **_ctx(),
    )


def register_entity_views(admin_bp):
    @admin_bp.get("/customers")
    def customers():
        rows = Customer.query.order_by(Customer.id.desc()).limit(200).all()
        return render_template(
            "admin/customers.html",
            title="العملاء",
            customers=rows,
            **build_admin_context(),
        )

    @admin_bp.route("/customers/<int:customer_id>", methods=["GET", "POST"])
    def customer_detail_page(customer_id):
        customer = db.session.get(Customer, customer_id)
        if customer is None:
            return render_template(
                "admin/module.html",
                title="العميل غير موجود",
                section="العملاء والتواصل",
                requested_path=request.path,
                **build_admin_context(),
            ), 404

        from ..models import (
            CustomerAddress, CustomerPricingAssignment, Order,
            Conversation, Wallet, CustomerNotification, Notification,
        )

        error = None
        success = None
        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                if action == "profile":
                    customer.name = (request.form.get("name") or "").strip() or None
                    customer.email = (request.form.get("email") or "").strip() or None
                    customer.status = (request.form.get("status") or customer.status).strip()
                    customer.city_id = request.form.get("city_id", type=int)
                    db.session.commit()
                    success = "تم حفظ بيانات العميل."
                elif action == "address":
                    address = CustomerAddress(
                        customer_id=customer.id,
                        recipient_name=(request.form.get("recipient_name") or "").strip(),
                        phone=(request.form.get("address_phone") or "").strip(),
                        city_id=request.form.get("address_city_id", type=int),
                        district=(request.form.get("district") or "").strip() or None,
                        street=(request.form.get("street") or "").strip() or None,
                        landmark=(request.form.get("landmark") or "").strip() or None,
                        is_default=request.form.get("is_default") == "on",
                    )
                    if not address.recipient_name or not address.phone:
                        raise ValueError("اسم المستلم ورقم الهاتف مطلوبان.")
                    if address.is_default:
                        CustomerAddress.query.filter_by(customer_id=customer.id, is_active=True).update(
                            {CustomerAddress.is_default: False}, synchronize_session=False
                        )
                    db.session.add(address)
                    db.session.commit()
                    success = "تمت إضافة العنوان."
                else:
                    raise ValueError("إجراء العميل غير معروف.")
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        orders = Order.query.filter_by(customer_id=customer.id).order_by(Order.id.desc()).limit(50).all()
        conversations = Conversation.query.filter_by(customer_id=customer.id).order_by(
            Conversation.last_message_at.desc(), Conversation.id.desc()
        ).limit(50).all()
        addresses = CustomerAddress.query.filter_by(
            customer_id=customer.id, is_active=True
        ).order_by(CustomerAddress.is_default.desc(), CustomerAddress.id).all()
        assignments = CustomerPricingAssignment.query.filter_by(
            customer_id=customer.id, is_active=True
        ).order_by(CustomerPricingAssignment.priority.desc(), CustomerPricingAssignment.id.desc()).all()
        wallets = Wallet.query.filter_by(customer_id=customer.id, is_active=True).all()
        notifications = (
            db.session.query(CustomerNotification, Notification)
            .join(Notification, Notification.id == CustomerNotification.notification_id)
            .filter(CustomerNotification.customer_id == customer.id)
            .order_by(CustomerNotification.id.desc())
            .limit(50).all()
        )

        cities = []
        try:
            from ..models import City
            cities = City.query.filter_by(is_active=True).order_by(City.name).all()
        except Exception:
            db.session.rollback()

        return render_template(
            "admin/customer_detail.html",
            title=f"العميل · {customer.name or customer.phone_normalized}",
            customer=customer,
            orders=orders,
            conversations=conversations,
            addresses=addresses,
            pricing_assignments=assignments,
            wallets=wallets,
            notifications=notifications,
            cities=cities,
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.get("/orders")
    def orders():
        rows = Order.query.order_by(Order.id.desc()).limit(200).all()
        return render_template(
            "admin/orders.html",
            title="الطلبات",
            orders=rows,
            **build_admin_context(),
        )

    @admin_bp.route("/orders/<int:order_id>", methods=["GET", "POST"])
    def order_detail_page(order_id):
        order = db.session.get(Order, order_id)
        if order is None:
            return render_template(
                "admin/module.html",
                title="الطلب غير موجود",
                section="المبيعات والطلبات",
                requested_path=request.path,
                **build_admin_context(),
            ), 404

        error = None
        success = None
        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                if action == "status":
                    CommerceService.transition_order(
                        order.id,
                        str(request.form["status"]),
                        actor_type="admin",
                        actor_id=session.get("admin_id"),
                        note=(request.form.get("note") or "").strip() or None,
                    )
                    success = "تم تحديث حالة الطلب."
                elif action == "message":
                    conversation = Conversation.query.filter_by(order_id=order.id).order_by(Conversation.id.desc()).first()
                    if conversation is None:
                        conversation = Conversation(
                            customer_id=order.customer_id,
                            order_id=order.id,
                            type="order_support",
                            subject=f"الطلب {order.order_no}",
                            status="open",
                        )
                        db.session.add(conversation)
                        db.session.commit()
                    SupportService.send_message(
                        conversation.id,
                        "admin",
                        session.get("admin_id") or 0,
                        (request.form.get("body") or "").strip(),
                        "text",
                    )
                    success = "تم إرسال الرسالة للعميل."
                else:
                    raise ValueError("إجراء الطلب غير معروف.")
            except (KeyError, ValueError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)

            order = db.session.get(Order, order_id)

        detail = CommerceService.serialize_order_detail(order)
        return render_template(
            "admin/order_detail.html",
            title=f"الطلب {order.order_no}",
            order=detail,
            status_choices=(
                "created", "awaiting_payment", "paid", "processing",
                "shipped", "delivered", "returned", "cancelled",
            ),
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.get("/chat")
    def chat():
        rows = Conversation.query.order_by(Conversation.last_message_at.desc(), Conversation.id.desc()).limit(200).all()
        return _render("المحادثات", ["ID", "العميل", "الطلب", "النوع", "الحالة"],
                       [[x.id, x.customer_id, x.order_id or "—", x.type, x.status] for x in rows],
                       "العملاء والتواصل")

    @admin_bp.route("/payments", methods=["GET", "POST"])
    def payments():
        from ..models import Currency, Order, PaymentMethod
        error = None
        success = None
        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                from ..modules.commerce.payment_shipping import PaymentShippingService
                if action == "method":
                    PaymentShippingService.create_payment_method({
                        "name": request.form.get("name"),
                        "code": request.form.get("code"),
                        "provider": request.form.get("provider"),
                        "supports_proof": request.form.get("supports_proof") == "on",
                    })
                    success = "تم إنشاء طريقة الدفع."
                elif action == "transaction":
                    PaymentShippingService.record_payment({
                        "order_id": request.form.get("order_id"),
                        "method_id": request.form.get("method_id"),
                        "currency_id": request.form.get("currency_id"),
                        "amount": request.form.get("amount"),
                        "provider_ref": request.form.get("provider_ref"),
                        "status": request.form.get("status", "pending"),
                    })
                    success = "تم تسجيل عملية الدفع."
                else:
                    raise ValueError("إجراء الدفع غير معروف.")
            except (KeyError, ValueError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)

        transactions = PaymentTransaction.query.order_by(PaymentTransaction.id.desc()).limit(200).all()
        methods = PaymentMethod.query.filter_by(is_active=True).order_by(PaymentMethod.name).all()
        orders = Order.query.order_by(Order.id.desc()).limit(200).all()
        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        return render_template(
            "admin/payments.html",
            title="الدفعات",
            transactions=transactions,
            methods=methods,
            orders=orders,
            currencies=currencies,
            success=success,
            error=error,
            **build_admin_context(),
        )

    @admin_bp.route("/shipping", methods=["GET", "POST"])
    def shipping():
        from ..models import Order, ShippingMethod, Shipment
        error = None
        success = None
        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                from ..modules.commerce.payment_shipping import PaymentShippingService
                if action == "method":
                    PaymentShippingService.create_shipping_method({
                        "name": request.form.get("name"),
                        "code": request.form.get("code"),
                        "delivery_days_min": request.form.get("delivery_days_min", type=int),
                        "delivery_days_max": request.form.get("delivery_days_max", type=int),
                        "supports_cod": request.form.get("supports_cod") == "on",
                    })
                    success = "تم إنشاء طريقة الشحن."
                elif action == "shipment":
                    event_status = (request.form.get("event_status") or "").strip()
                    PaymentShippingService.create_shipment({
                        "order_id": request.form.get("order_id"),
                        "shipping_method_id": request.form.get("shipping_method_id", type=int),
                        "tracking_no": (request.form.get("tracking_no") or "").strip() or None,
                        "status": request.form.get("status", "pending"),
                        "event": {
                            "status": event_status or request.form.get("status", "pending"),
                            "location": (request.form.get("event_location") or "").strip() or None,
                            "description": (request.form.get("event_description") or "").strip() or None,
                        },
                    })
                    success = "تم إنشاء الشحنة وتسجيل الحدث الأول."
                elif action == "event":
                    PaymentShippingService.add_shipment_event(
                        request.form.get("shipment_id", type=int),
                        {
                            "status": request.form.get("event_status"),
                            "location": request.form.get("event_location"),
                            "description": request.form.get("event_description"),
                        },
                    )
                    success = "تمت إضافة حدث الشحن."
                else:
                    raise ValueError("إجراء الشحن غير معروف.")
            except (KeyError, ValueError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)

        methods = ShippingMethod.query.filter_by(is_active=True).order_by(ShippingMethod.name).all()
        shipments = Shipment.query.order_by(Shipment.id.desc()).limit(200).all()
        orders = Order.query.order_by(Order.id.desc()).limit(200).all()
        return render_template(
            "admin/shipping.html",
            title="الشحن والتتبع",
            methods=methods,
            shipments=shipments,
            orders=orders,
            success=success,
            error=error,
            **build_admin_context(),
        )

    @admin_bp.get("/returns")
    def returns():
        from ..models import ReturnRequest
        rows = ReturnRequest.query.order_by(ReturnRequest.id.desc()).limit(200).all()
        return _render("الإرجاع والاسترداد", ["ID", "الطلب", "العميل", "السبب", "الحالة"],
                       [[x.id, x.order_id, x.customer_id, x.reason, x.status] for x in rows],
                       "المبيعات والطلبات")

    @admin_bp.get("/warranty")
    def warranty():
        from ..models import WarrantyClaim
        rows = WarrantyClaim.query.order_by(WarrantyClaim.id.desc()).limit(200).all()
        return _render("الضمان", ["ID", "الطلب", "الصنف", "المشكلة", "الحالة"],
                       [[x.id, x.order_id, x.order_item_id, x.issue, x.status] for x in rows],
                       "المبيعات والطلبات")

    @admin_bp.get("/reviews")
    def reviews():
        rows = Review.query.order_by(Review.id.desc()).limit(200).all()
        return _render("التقييمات", ["ID", "المنتج", "العميل", "التقييم", "الحالة"],
                       [[x.id, x.product_id, x.customer_id, x.rating, x.status] for x in rows],
                       "المبيعات والطلبات")

    @admin_bp.get("/promotions/coupons")
    def coupons():
        rows = Coupon.query.order_by(Coupon.id.desc()).limit(200).all()
        return _render("الكوبونات", ["ID", "الكود", "النوع", "القيمة", "حد الاستخدام"],
                       [[x.id, x.code, x.type, x.value, x.usage_limit or "غير محدد"] for x in rows],
                       "الترويج والمالية")

    @admin_bp.get("/promotions/gifts")
    def gifts():
        from ..models import GiftCampaign
        rows = GiftCampaign.query.order_by(GiftCampaign.id.desc()).limit(200).all()
        return _render("الهدايا", ["ID", "الاسم", "النوع", "القيمة"],
                       [[x.id, x.name, x.gift_type, x.value or "—"] for x in rows],
                       "الترويج والمالية")

    @admin_bp.get("/finance/wallets")
    def wallets():
        rows = Wallet.query.order_by(Wallet.id.desc()).limit(200).all()
        return _render("محافظ العملاء", ["ID", "العميل", "العملة", "الرصيد", "الحالة"],
                       [[x.id, x.customer_id, x.currency_id, x.balance, x.status] for x in rows],
                       "الترويج والمالية")

    @admin_bp.get("/system/admins")
    def admins():
        from ..models import Admin
        rows = Admin.query.order_by(Admin.username).all()
        return _render("المستخدمون", ["ID", "المستخدم", "البريد", "الهاتف", "الحالة"],
                       [[x.id, x.username, x.email or "—", x.phone or "—", x.status] for x in rows],
                       "النظام")

    @admin_bp.get("/system/roles")
    def roles():
        rows = Role.query.order_by(Role.name).all()
        return _render("الأدوار والصلاحيات", ["ID", "الدور", "الكود"],
                       [[x.id, x.name, x.code] for x in rows],
                       "النظام")

    @admin_bp.get("/system/audit")
    def audit():
        rows = AuditLog.query.order_by(AuditLog.id.desc()).limit(200).all()
        return _render("سجل التدقيق", ["ID", "العملية", "الكيان", "المعرف", "المدير"],
                       [[x.id, x.action, x.entity_type, x.entity_id or "—", x.admin_id or "—"] for x in rows],
                       "النظام")

    @admin_bp.get("/system/theme")
    def theme():
        rows = Theme.query.order_by(Theme.name).all()
        return _render("الثيم", ["ID", "الاسم", "الكود", "الحالة"],
                       [[x.id, x.name, x.code, "نشط" if x.is_active else "متوقف"] for x in rows],
                       "النظام")



    @admin_bp.get("/tasks")
    def tasks():
        from ..models import PaymentProof, ReturnRequest, WarrantyClaim
        rows = []
        for x in PaymentProof.query.filter_by(status="pending").limit(50).all():
            rows.append(["دفع", x.id, x.order_id, x.status])
        for x in ReturnRequest.query.filter_by(status="requested").limit(50).all():
            rows.append(["إرجاع", x.id, x.order_id, x.status])
        for x in WarrantyClaim.query.filter_by(status="submitted").limit(50).all():
            rows.append(["ضمان", x.id, x.order_id, x.status])
        return _render("الأعمال المعلقة", ["النوع", "ID", "الطلب", "الحالة"], rows, "الرئيسية")

    @admin_bp.get("/notifications")
    def notifications():
        from ..models import Notification
        rows = Notification.query.order_by(Notification.id.desc()).limit(200).all()
        return _render("الإشعارات", ["ID", "العميل", "النوع", "العنوان", "الحالة"],
                       [[x.id, x.customer_id, x.type, x.title, x.status] for x in rows], "العملاء والتواصل")

    @admin_bp.get("/products/drafts")
    def product_drafts():
        from ..models import Product
        rows = Product.query.filter_by(status="draft").order_by(Product.id.desc()).limit(200).all()
        return _render("مسودات المنتجات", ["ID", "SKU", "الاسم", "السعر", "الحالة"],
                       [[x.id, x.sku, x.name, x.base_price, x.status] for x in rows], "الكتالوج")

    @admin_bp.get("/brands")
    def brands():
        from ..models import Brand
        rows = Brand.query.filter_by(is_active=True).order_by(Brand.name).all()
        return _render("العلامات التجارية", ["ID", "الاسم", "Slug", "Logo"],
                       [[x.id, x.name, x.slug, x.logo_asset_id or "—"] for x in rows], "الكتالوج")

    @admin_bp.get("/options")
    def options():
        from ..models import Color, Size
        colors = Color.query.filter_by(is_active=True).order_by(Color.sort_order, Color.name).limit(200).all()
        sizes = Size.query.filter_by(is_active=True).order_by(Size.group, Size.sort_order, Size.label).limit(200).all()
        rows = (
            [["لون", x.id, x.name, x.hex_code or "—", x.sort_order] for x in colors]
            + [["مقاس", x.id, f"{x.group} / {x.code}", x.label, x.sort_order] for x in sizes]
        )
        return _render("الألوان والمقاسات", ["النوع", "ID", "الاسم/الكود", "القيمة", "الترتيب"], rows, "الكتالوج")

    @admin_bp.get("/category-strip")
    def category_strip():
        from ..models import CategoryNavigationItem
        rows = CategoryNavigationItem.query.filter_by(is_active=True).order_by(CategoryNavigationItem.sort_order).limit(200).all()
        return _render("شريط الأقسام", ["ID", "الفئة", "Slot", "الترتيب", "ظاهر"],
                       [[x.id, x.category_id, x.slot, x.sort_order, "نعم" if x.visible else "لا"] for x in rows], "الكتالوج")

    @admin_bp.get("/storefront/pages")
    def storefront_pages():
        from ..models import StorefrontPage, StorefrontSection, StorefrontSectionItem
        pages = StorefrontPage.query.filter_by(is_active=True).order_by(StorefrontPage.id).all()
        sections = StorefrontSection.query.order_by(StorefrontSection.page_id, StorefrontSection.sort_order).limit(1000).all()
        section_ids = [row.id for row in sections]
        items = StorefrontSectionItem.query.filter(
            StorefrontSectionItem.section_id.in_(section_ids)
        ).order_by(StorefrontSectionItem.section_id, StorefrontSectionItem.sort_order, StorefrontSectionItem.id).all() if section_ids else []
        items_by_section = {}
        for item in items:
            items_by_section.setdefault(item.section_id, []).append(item)
        return render_template(
            "admin/storefront_pages.html",
            title="صفحات المتجر",
            pages=pages,
            sections=sections,
            items_by_section=items_by_section,
            **build_admin_context(),
        )

    @admin_bp.post("/storefront/pages")
    def storefront_create_page():
        from ..models import StorefrontPage
        code = (request.form.get("code") or "").strip().lower()
        name = (request.form.get("name") or "").strip()
        route = (request.form.get("route") or "").strip()
        if not code or not name or not route:
            return render_template(
                "admin/module.html",
                title="بيانات الصفحة ناقصة",
                section="المحتوى والمتجر",
                requested_path="/admin/storefront/pages",
                **build_admin_context(),
            ), 400
        if StorefrontPage.query.filter(
            (StorefrontPage.code == code) | (StorefrontPage.route == route)
        ).first():
            return render_template(
                "admin/module.html",
                title="الصفحة موجودة مسبقًا",
                section="المحتوى والمتجر",
                requested_path="/admin/storefront/pages",
                **build_admin_context(),
            ), 400
        db.session.add(StorefrontPage(code=code, name=name, route=route))
        db.session.commit()
        return __import__("flask").redirect("/admin/storefront/pages")

    @admin_bp.post("/storefront/sections")
    def storefront_create_section():
        from ..models import StorefrontPage, StorefrontSection
        page_id = request.form.get("page_id", type=int)
        section_type = (request.form.get("section_type") or "product_grid").strip()
        title = (request.form.get("title") or "").strip() or None
        if db.session.get(StorefrontPage, page_id) is None:
            return {"error": "page_not_found"}, 404
        db.session.add(StorefrontSection(
            page_id=page_id,
            section_type=section_type,
            title=title,
            sort_order=request.form.get("sort_order", 0, type=int),
            settings={},
            visible_rules={},
        ))
        db.session.commit()
        return __import__("flask").redirect("/admin/storefront/pages")

    @admin_bp.post("/storefront/sections/<int:section_id>/items")
    def storefront_add_item(section_id):
        from ..models import StorefrontSection, StorefrontSectionItem
        section = db.session.get(StorefrontSection, section_id)
        if section is None:
            return {"error": "section_not_found"}, 404
        db.session.add(StorefrontSectionItem(
            section_id=section.id,
            item_type=(request.form.get("item_type") or "product").strip(),
            item_id=request.form.get("item_id", type=int),
            sort_order=request.form.get("sort_order", 0, type=int),
            custom_label=(request.form.get("custom_label") or "").strip() or None,
        ))
        db.session.commit()
        return __import__("flask").redirect("/admin/storefront/pages")

    @admin_bp.get("/banner-targets")
    def banner_targets():
        from ..models import BannerTarget
        rows = BannerTarget.query.order_by(BannerTarget.banner_id, BannerTarget.priority.desc()).limit(500).all()
        return _render("أهداف البانرات", ["ID", "Banner", "النوع", "الهدف", "الرابط"],
                       [[x.id, x.banner_id, x.target_type, x.target_id or "—", x.url or "—"] for x in rows], "المحتوى والمتجر")

    @admin_bp.get("/category-circles")
    def category_circles():
        from ..models import Category
        rows = Category.query.filter(Category.is_active.is_(True), Category.display_style == "circle").order_by(Category.sort_order, Category.name).limit(200).all()
        return _render("دوائر الفئات", ["ID", "الفئة", "الأب", "الترتيب"],
                       [[x.id, x.name, x.parent_id or "—", x.sort_order] for x in rows], "المحتوى والمتجر")

    @admin_bp.get("/trends")
    def trends():
        from ..models import Hashtag
        rows = Hashtag.query.filter_by(is_active=True).order_by(Hashtag.sort_order, Hashtag.id.desc()).limit(300).all()
        return _render("الترندات والهاشتاجات", ["ID", "الاسم", "Slug", "الترتيب"],
                       [[x.id, x.display_name or x.name, x.slug, x.sort_order] for x in rows], "المحتوى والمتجر")

    @admin_bp.get("/storefront/collections")
    def storefront_collections():
        from ..models import PromotionalStrip
        rows = PromotionalStrip.query.filter_by(is_active=True).order_by(PromotionalStrip.id.desc()).limit(200).all()
        return _render("جديدنا والعروض", ["ID", "الاسم", "النص", "الخلفية"],
                       [[x.id, x.name, x.text_body, x.background_color or "—"] for x in rows], "المحتوى والمتجر")

    @admin_bp.get("/geo")
    def geo():
        from ..models import City, Country, Region
        rows = (
            [["دولة", x.id, x.code, x.name_ar] for x in Country.query.filter_by(is_active=True).all()]
            + [["منطقة", x.id, x.code, x.name] for x in Region.query.filter_by(is_active=True).all()]
            + [["مدينة", x.id, x.code, x.name] for x in City.query.filter_by(is_active=True).all()]
        )
        return _render("المناطق والمدن", ["النوع", "ID", "الكود", "الاسم"], rows, "التسعير")

    @admin_bp.get("/payments/proofs")
    def payment_proofs():
        from ..models import PaymentProof
        rows = PaymentProof.query.order_by(PaymentProof.id.desc()).limit(200).all()
        return _render("إثباتات الدفع", ["ID", "الطلب", "المعاملة", "Asset", "الحالة"],
                       [[x.id, x.order_id, x.transaction_id or "—", x.asset_id, x.status] for x in rows], "المبيعات والطلبات")

    @admin_bp.get("/customers/addresses")
    def customer_addresses():
        from ..models import CustomerAddress
        rows = CustomerAddress.query.order_by(CustomerAddress.id.desc()).limit(300).all()
        return _render("عناوين العملاء", ["ID", "العميل", "المستلم", "الهاتف", "المدينة"],
                       [[x.id, x.customer_id, x.recipient_name, x.phone, x.city_id or "—"] for x in rows], "العملاء والتواصل")

    @admin_bp.get("/attachments")
    def attachments():
        from ..models import MessageAttachment
        rows = MessageAttachment.query.order_by(MessageAttachment.id.desc()).limit(300).all()
        return _render("مرفقات المحادثات", ["ID", "الرسالة", "Asset", "النوع"],
                       [[x.id, x.message_id, x.asset_id, x.mime_type] for x in rows], "العملاء والتواصل")

    @admin_bp.get("/finance/wallet-ledger")
    def wallet_ledger():
        from ..models import WalletTransaction
        rows = WalletTransaction.query.order_by(WalletTransaction.id.desc()).limit(300).all()
        return _render("دفتر حركات المحافظ", ["ID", "المحفظة", "النوع", "المبلغ", "بعد الحركة"],
                       [[x.id, x.wallet_id, x.type, x.amount, x.balance_after] for x in rows], "الترويج والمالية")

    @admin_bp.get("/reports")
    def reports():
        from ..models import Order, Product, ProductVariant, StockInventory
        orders_total = db.session.query(func.coalesce(func.sum(Order.total), 0)).filter(Order.status != "cancelled").scalar()
        products_count = db.session.query(func.count(Product.id)).scalar() or 0
        variants_count = db.session.query(func.count(ProductVariant.id)).scalar() or 0
        available_stock = db.session.query(func.coalesce(func.sum(StockInventory.available), 0)).scalar() or 0
        rows = [
            ["مبيعات", "إجمالي الطلبات غير الملغاة", orders_total],
            ["كتالوج", "المنتجات", products_count],
            ["كتالوج", "المتغيرات", variants_count],
            ["مخزون", "المتاح", available_stock],
        ]
        return _render("التقارير", ["المجال", "المؤشر", "القيمة"], rows, "الترويج والمالية")

    @admin_bp.get("/system/settings")
    def settings():
        from ..models import AppSetting
        rows = AppSetting.query.order_by(AppSetting.group_code, AppSetting.key).limit(500).all()
        return _render("الإعدادات", ["المجموعة", "المفتاح", "القيمة", "النوع"],
                       [[x.group_code, x.key, x.value or "—", x.value_type] for x in rows], "النظام")

    @admin_bp.get("/system/features")
    def features():
        rows = FeatureFlag.query.order_by(FeatureFlag.key).all()
        return _render("المزايا", ["ID", "المفتاح", "التفعيل"],
                       [[x.id, x.key, "مفعلة" if x.enabled else "متوقفة"] for x in rows],
                       "النظام")

    @admin_bp.get("/pricing/currencies")
    def currencies():
        from ..models import Currency
        rows = Currency.query.order_by(Currency.code).all()
        return _render("العملات", ["ID", "الكود", "الاسم", "الرمز", "أساس"],
                       [[x.id, x.code, x.name_ar, x.symbol or "—", "نعم" if x.is_base else "لا"] for x in rows],
                       "التسعير")

    @admin_bp.get("/pricing/rates")
    def rates():
        rows = ExchangeRate.query.order_by(ExchangeRate.valid_from.desc()).limit(200).all()
        return _render("أسعار الصرف", ["ID", "من", "إلى", "السعر", "يبدأ"],
                       [[x.id, x.base_currency_id, x.quote_currency_id, x.rate, x.valid_from] for x in rows],
                       "التسعير")

    @admin_bp.get("/pricing/city-assignments")
    def city_assignments():
        rows = PricingGroupCity.query.order_by(PricingGroupCity.priority.desc(), PricingGroupCity.id.desc()).limit(200).all()
        return _render("ربط المدن بالمجموعات", ["ID", "المدينة", "المنطقة", "المجموعة", "الأولوية"],
                       [[x.id, x.city_id or "—", x.region_id or "—", x.pricing_group_id, x.priority] for x in rows],
                       "التسعير")

    @admin_bp.get("/pricing/customer-assignments")
    def customer_assignments():
        from ..models import CustomerPricingAssignment
        rows = CustomerPricingAssignment.query.order_by(CustomerPricingAssignment.priority.desc(), CustomerPricingAssignment.id.desc()).limit(200).all()
        return _render("تعيينات العملاء", ["ID", "العميل", "المجموعة", "% override", "ثابت"],
                       [[x.id, x.customer_id, x.pricing_group_id, x.percent_override or 0, x.fixed_override or 0] for x in rows],
                       "التسعير")

    @admin_bp.get("/inventory")
    def inventory():
        rows = ProductVariant.query.order_by(ProductVariant.id.desc()).limit(200).all()
        return _render("المتغيرات والمخزون", ["ID", "المنتج", "SKU", "اللون", "المقاس"],
                       [[x.id, x.product_id, x.sku, x.color_id or "—", x.size_id or "—"] for x in rows],
                       "الكتالوج")

    @admin_bp.get("/media")
    def media():
        rows = ProductMedia.query.order_by(ProductMedia.id.desc()).limit(200).all()
        return _render("مكتبة الوسائط", ["ID", "المنتج", "Asset", "الدور"],
                       [[x.id, x.product_id, x.asset_id, x.role] for x in rows],
                       "الكتالوج")

    @admin_bp.get("/product-settings")
    def product_settings():
        rows = ProductDisplaySettings.query.order_by(ProductDisplaySettings.product_id).limit(200).all()
        return _render("إعدادات المنتج", ["المنتج", "التقييم", "تم البيع", "الشحن", "الإرجاع"],
                       [[x.product_id, x.show_rating, x.show_sold_badge, x.show_shipping_banner, x.show_return] for x in rows],
                       "الكتالوج")
