from sqlalchemy import func

from flask import request

from ..extensions import db
from ..models import Conversation, Message, Notification, Order
from .navigation import NAVIGATION, NavItem, NavSection

ORDER_STATUS_LABELS = {
    "created": "بانتظار الموافقة",
    "awaiting_payment": "بانتظار الدفع",
    "paid": "قيد التجهيز",
    "processing": "قيد التجهيز",
    "shipped": "تم الشحن",
    "in_transit": "في الطريق",
    "delivered": "تم التسليم",
    "returned": "تمت الإعادة",
    "cancelled": "ملغاة",
    "canceled": "ملغاة",
}

PAYMENT_STATUS_LABELS = {
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
