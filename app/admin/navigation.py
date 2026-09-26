from dataclasses import dataclass, field


@dataclass(frozen=True)
class NavItem:
    label: str
    route: str
    icon: str
    badge_key: str | None = None


@dataclass
class NavSection:
    label: str
    icon: str
    children: list[NavItem] = field(default_factory=list)
    active: bool = False


NAVIGATION = [
    NavSection("الرئيسية", "⌂", [
        NavItem("لوحة التحكم", "/admin/", "▦"),
        NavItem("الأعمال المعلقة", "/admin/tasks", "•"),
        NavItem("التنبيهات", "/admin/notifications", "!", "notifications"),
    ]),
    NavSection("الكتالوج", "□", [
        NavItem("المنتجات", "/admin/products", "□"),
        NavItem("إضافة منتج", "/admin/products/new", "+"),
        NavItem("المسودات", "/admin/products/drafts", "D"),
        NavItem("التصنيفات", "/admin/categories", "▤"),
        NavItem("شريط الأقسام", "/admin/category-strip", "≡"),
        NavItem("العلامات التجارية", "/admin/brands", "T"),
        NavItem("الألوان والمقاسات", "/admin/options", "●"),
        NavItem("المتغيرات والمخزون", "/admin/inventory", "L"),
        NavItem("مكتبة الوسائط", "/admin/media", "▧"),
        NavItem("الشارات والسياسات", "/admin/catalog/policies", "✓"),
    ]),
    NavSection("المحتوى والمتجر", "◇", [
        NavItem("صفحات المتجر", "/admin/storefront/pages", "□"),
        NavItem("أقسام الصفحة", "/admin/storefront/sections", "▦"),
        NavItem("البانرات", "/admin/banners", "▧"),
        NavItem("الأهداف والروابط", "/admin/banner-targets", "↗"),
        NavItem("دوائر الفئات", "/admin/category-circles", "○"),
        NavItem("الفئات الجانبية", "/admin/side-categories", "◉"),
        NavItem("الترندات والهاشتاجات", "/admin/trends", "#"),
        NavItem("الحملات", "/admin/campaigns", "✦"),
        NavItem("جديدنا والعروض", "/admin/storefront/collections", "★"),
    ]),
    NavSection("التسعير", "¤", [
        NavItem("مجموعات التسعير", "/admin/pricing/groups", "¤"),
        NavItem("العملات", "/admin/pricing/currencies", "$"),
        NavItem("أسعار الصرف (SAR)", "/admin/pricing/exchange-rates", "↻"),
        NavItem("المدن والمناطق", "/admin/geo", "⌖"),
        NavItem("ربط التسعير حسب المدينة", "/admin/pricing/groups", "↔"),
        NavItem("استثناءات العملاء", "/admin/pricing/customer-overrides", "♙"),
        NavItem("معاينة السعر", "/admin/pricing/preview", "≈"),
    ]),
    NavSection("المبيعات والطلبات", "▣", [
        NavItem("الطلبات", "/admin/orders", "▣", "orders"),
        NavItem("الدفع", "/admin/payments", "¤"),
        NavItem("إثباتات الدفع", "/admin/payments/proofs", "▧"),
        NavItem("الشحن والتتبع", "/admin/shipping", "→"),
        NavItem("طرق التوصيل وقواعدها", "/admin/shipping/rates", "⌁"),
        NavItem("الإرجاع والاسترداد", "/admin/returns", "↶"),
        NavItem("الضمان", "/admin/warranty", "✓"),
        NavItem("التقييمات", "/admin/reviews", "★"),
    ]),
    NavSection("العملاء والتواصل", "◎", [
        NavItem("العملاء", "/admin/customers", "◎"),
        NavItem("العناوين", "/admin/customers/addresses", "⌖"),
        NavItem("المحادثات", "/admin/chat", "…", "unread_chats"),
        NavItem("الإشعارات", "/admin/notifications", "!"),
        NavItem("الملفات", "/admin/attachments", "↗"),
    ]),
    NavSection("الترويج والمالية", "☆", [
        NavItem("الكوبونات", "/admin/promotions/coupons", "%"),
        NavItem("الهدايا", "/admin/promotions/gifts", "☆"),
        NavItem("المحافظ", "/admin/finance/wallets", "¤"),
        NavItem("حركات المحافظ", "/admin/finance/wallet-ledger", "≡"),
        NavItem("التقارير", "/admin/reports", "▥"),
    ]),
    NavSection("التكاملات", "◉", [
        NavItem("WhatsApp", "/admin/whatsapp", "◉"),
    ]),
    NavSection("النظام", "⚙", [
        NavItem("المستخدمون", "/admin/system/admins", "◎"),
        NavItem("الأدوار والصلاحيات", "/admin/system/roles", "🔑"),
        NavItem("سجل التدقيق", "/admin/system/audit", "↶"),
        NavItem("الثيم", "/admin/system/theme", "●"),
        NavItem("الإعدادات", "/admin/system/settings", "⚙"),
        NavItem("المزايا", "/admin/system/features", "◐"),
    ]),
]
