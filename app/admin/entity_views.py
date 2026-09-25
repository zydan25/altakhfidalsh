from flask import render_template, request

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
from .navigation import NAVIGATION


def _ctx():
    current_path = request.path
    items = []
    for section in NAVIGATION:
        section.active = any(current_path == child.route or current_path.startswith(child.route + "/") for child in section.children)
        for child in section.children:
            items.append({"label": child.label, "route": child.route, "section": section.label})
    return {"navigation": NAVIGATION, "current_path": current_path, "page_item_map": items}


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
        return _render("الطلبات", ["الطلب", "العميل", "الإجمالي", "الحالة", "الدفع", "الشحن"],
                       [[x.order_no, x.customer_id, x.total, x.status, x.payment_status, x.shipping_status] for x in rows],
                       "المبيعات والطلبات")

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
