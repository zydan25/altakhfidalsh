from sqlalchemy import func

from flask import request

from ..extensions import db
from ..models import Conversation, Message, Notification, Order
from .navigation import NAVIGATION, NavItem, NavSection

ORDER_STATUS_LABELS = {
    "created": "بانتظار موافقة الطلب",
    "awaiting_payment": "بانتظار الدفع",
    "paid": "تم الدفع",
    "processing": "قيد التجهيز",
    "shipped": "تم الشحن",
    "in_transit": "في الطريق",
    "delivered": "تم التسليم",
    "returned": "تمت الإعادة",
    "cancelled": "ملغاة",
    "canceled": "ملغاة",
    "shiped": "تم الشحن",
    "proccessing": "قيد التجهيز",
    "intransit": "في الطريق",
}

PAYMENT_STATUS_LABELS = {
    "cod": "الدفع عند الاستلام",
    "unpaid": "غير مدفوع",
    "pending": "قيد الانتظار",
    "pending_proof": "بانتظار مراجعة إثبات الدفع",
    "cod_pending": "بانتظار التحصيل عند الاستلام",
    "paid": "تم الدفع",
    "success": "ناجح",
    "successful": "ناجح",
    "completed": "مكتمل",
    "approved": "مقبول",
    "authorized": "تم التفويض",
    "failed": "فشل الدفع",
    "rejected": "مرفوض",
    "declined": "مرفوض",
    "refunded": "تم الاسترداد",
    "partially_refunded": "استرداد جزئي",
    "cancelled": "ملغاة",
    "canceled": "ملغاة",
    "voided": "ملغاة",
}

SHIPPING_STATUS_LABELS = {
    "pending": "بانتظار الشحن",
    "created": "تم إنشاء الشحنة",
    "label_created": "تم تجهيز بوليصة الشحن",
    "ready": "جاهزة للشحن",
    "picked_up": "استلمتها شركة الشحن",
    "in_transit": "في الطريق",
    "out_for_delivery": "خرجت للتسليم",
    "delivered": "تم التسليم",
    "exception": "يوجد تحديث على الشحنة",
    "returned": "مرتجع",
    "cancelled": "ملغاة",
    "canceled": "ملغاة",
    "shipped": "تم الشحن",
}

RECORD_STATUS_LABELS = {
    "pending": "قيد الانتظار",
    "requested": "تم تقديم الطلب",
    "submitted": "تم التقديم",
    "open": "مفتوح",
    "in_progress": "قيد المعالجة",
    "processing": "قيد المعالجة",
    "approved": "مقبول",
    "accepted": "مقبول",
    "rejected": "مرفوض",
    "declined": "مرفوض",
    "received": "تم الاستلام",
    "inspecting": "قيد الفحص",
    "completed": "مكتمل",
    "closed": "مغلق",
    "cancelled": "ملغى",
    "canceled": "ملغى",
    "refunded": "تم الاسترداد",
    "partially_refunded": "استرداد جزئي",
    "active": "نشط",
    "inactive": "غير نشط",
}

ACTOR_LABELS = {
    "admin": "الإدارة",
    "customer": "العميل",
    "system": "النظام",
    "employee": "الموظف",
}



ADMIN_THEME_ICONS = {
    "section:الرئيسية":"bi-house-door-fill","section:الكتالوج":"bi-box-seam-fill",
    "section:المحتوى والمتجر":"bi-shop-window","section:التسعير":"bi-currency-exchange",
    "section:المبيعات والطلبات":"bi-bag-check-fill","section:العملاء والتواصل":"bi-people-fill",
    "section:الترويج والمالية":"bi-megaphone-fill","section:التكاملات":"bi-plug-fill","section:النظام":"bi-gear-fill",
    "/admin/":"bi-grid-1x2-fill","/admin/tasks":"bi-list-check","/admin/notifications":"bi-bell-fill",
    "/admin/products":"bi-box-seam-fill","/admin/products/new":"bi-plus-square-fill","/admin/products/drafts":"bi-file-earmark-text-fill",
    "/admin/categories":"bi-diagram-3-fill","/admin/category-home-display":"bi-grid-fill","/admin/category-strip":"bi-view-stacked",
    "/admin/brands":"bi-tags-fill","/admin/options":"bi-palette2","/admin/size-guides":"bi-rulers",
    "/admin/inventory":"bi-boxes","/admin/media":"bi-images","/admin/badges":"bi-patch-check-fill",
    "/admin/catalog/policies":"bi-shield-check","/admin/storefront/pages":"bi-file-text-fill","/admin/storefront/sections":"bi-layout-text-window-reverse",
    "/admin/banners":"bi-images","/admin/banner-targets":"bi-link-45deg","/admin/category-circles":"bi-circle",
    "/admin/side-categories":"bi-list-nested","/admin/trends":"bi-graph-up-arrow","/admin/trends/display-settings":"bi-card-image",
    "/admin/product-detail-settings":"bi-sliders","/admin/looks":"bi-stars","/admin/store-locations":"bi-geo-alt-fill",
    "/admin/campaigns":"bi-megaphone-fill","/admin/storefront/collections":"bi-stars","/admin/pricing/groups":"bi-currency-exchange",
    "/admin/pricing/currencies":"bi-cash-coin","/admin/pricing/exchange-rates":"bi-arrow-left-right","/admin/geo":"bi-geo-fill",
    "/admin/pricing/location-adjustments":"bi-sliders2","/admin/pricing/customer-overrides":"bi-person-gear","/admin/pricing/preview":"bi-calculator-fill",
    "/admin/orders":"bi-bag-check-fill","/admin/payments":"bi-credit-card-2-front-fill","/admin/payments/proofs":"bi-receipt",
    "/admin/shipping":"bi-truck","/admin/shipping/rates":"bi-signpost-2-fill","/admin/returns":"bi-arrow-return-left",
    "/admin/warranty":"bi-shield-check","/admin/reviews":"bi-star-fill","/admin/customers":"bi-people-fill",
    "/admin/customers/addresses":"bi-pin-map-fill","/admin/chat":"bi-chat-dots-fill","/admin/attachments":"bi-paperclip",
    "/admin/promotions/coupons":"bi-ticket-perforated-fill","/admin/promotions/gifts":"bi-gift-fill",
    "/admin/finance/wallets":"bi-wallet2","/admin/finance/wallet-ledger":"bi-journal-text","/admin/reports":"bi-bar-chart-fill",
    "/admin/whatsapp":"bi-whatsapp","/admin/system/admins":"bi-person-badge-fill","/admin/system/roles":"bi-shield-lock-fill",
    "/admin/system/audit":"bi-clock-history","/admin/system/theme":"bi-palette-fill","/admin/system/layout":"bi-layout-wtf",
    "/admin/system/settings":"bi-gear-fill","/admin/system/features":"bi-toggles"
}

def build_admin_context():
    current_path = request.path
    sections = []
    page_item_map = []

    for source in NAVIGATION:
        children = [
            NavItem(
                label=item.label,
                route=item.route,
                icon=item.icon,
                badge_key=item.badge_key,
            )
            for item in source.children
        ]
        active = any(
            current_path == child.route
            or current_path.startswith(child.route + "/")
            for child in children
        )
        sections.append(
            NavSection(
                label=source.label,
                icon=source.icon,
                children=children,
                active=active,
            )
        )
        for child in children:
            page_item_map.append(
                {"label": child.label, "route": child.route, "section": source.label}
            )

    theme_values = {}
    try:
        from ..models import AppSetting
        for row in AppSetting.query.filter_by(group_code="theme").all():
            theme_values[row.key] = row.value
    except Exception:
        db.session.rollback()

    css_vars = "; ".join(
        f"--{key.replace('_', '-')}: {value}"
        for key, value in theme_values.items()
        if key.replace("_", "").isalnum() and value
    )

    return {
        "navigation": sections,
        "theme_css_vars": css_vars,
        "admin_layout_theme": theme_values.get("layout_theme", "classic") if theme_values.get("layout_theme", "classic") in {"classic", "water"} else "classic",
        "admin_theme_icons": ADMIN_THEME_ICONS,
        "current_path": current_path,
        "page_item_map": page_item_map,
        "order_status_labels": ORDER_STATUS_LABELS,
        "payment_status_labels": PAYMENT_STATUS_LABELS,
        "shipping_status_labels": SHIPPING_STATUS_LABELS,
        "record_status_labels": RECORD_STATUS_LABELS,
        "actor_labels": ACTOR_LABELS,
        "badge_counts": {
            "notifications": _safe_count(
                Notification, Notification.status.in_(("queued", "pending"))
            ),
            "orders": _safe_count(
                Order, Order.status.in_(("created", "awaiting_payment", "paid"))
            ),
            "unread_chats": _safe_unread_conversations(),
        },
    }


def _safe_count(model, criterion=None):
    try:
        query = db.session.query(func.count(model.id))
        if criterion is not None:
            query = query.filter(criterion)
        return query.scalar() or 0
    except Exception:
        db.session.rollback()
        return 0


def _safe_unread_conversations():
    try:
        return (
            db.session.query(func.count(func.distinct(Conversation.id)))
            .join(Message, Message.conversation_id == Conversation.id)
            .filter(
                Message.sender_type == "customer",
                Message.read_at.is_(None),
            )
            .scalar()
            or 0
        )
    except Exception:
        db.session.rollback()
        return 0
