from flask import redirect, render_template, request

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
        return _render("العملاء", ["ID", "الهاتف", "الاسم", "المدينة", "الحالة"],
                       [[x.id, x.phone_normalized, x.name or "—", x.city_id or "—", x.status] for x in rows],
                       "العملاء والتواصل")

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
                        actor_id=request.environ.get("admin_id"),
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
                        request.environ.get("admin_id") or 0,
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

    @admin_bp.get("/payments")
    def payments():
        rows = PaymentTransaction.query.order_by(PaymentTransaction.id.desc()).limit(200).all()
        return _render("الدفعات", ["ID", "الطلب", "المبلغ", "العملة", "الحالة"],
                       [[x.id, x.order_id, x.amount, x.currency_id, x.status] for x in rows],
                       "المبيعات والطلبات")

    @admin_bp.get("/shipping")
    def shipping():
        rows = ShippingMethod.query.order_by(ShippingMethod.id.desc()).limit(100).all()
        return _render("الشحن والتتبع", ["ID", "الطريقة", "الكود", "الأيام", "COD"],
                       [[x.id, x.name, x.code, f"{x.delivery_days_min or '—'}–{x.delivery_days_max or '—'}", "نعم" if x.supports_cod else "لا"] for x in rows],
                       "المبيعات والطلبات")

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
        from ..models import StorefrontPage
        rows = StorefrontPage.query.filter_by(is_active=True).order_by(StorefrontPage.id).all()
        return _render("صفحات المتجر", ["ID", "الكود", "الاسم", "المسار"],
                       [[x.id, x.code, x.name, x.route] for x in rows], "المحتوى والمتجر")

    @admin_bp.get("/storefront/sections")
    def storefront_sections():
        from ..models import StorefrontSection
        rows = StorefrontSection.query.order_by(StorefrontSection.page_id, StorefrontSection.sort_order).limit(500).all()
        return _render("أقسام الصفحة", ["ID", "Page", "النوع", "العنوان", "الترتيب"],
                       [[x.id, x.page_id, x.section_type, x.title or "—", x.sort_order] for x in rows], "المحتوى والمتجر")

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
