# اكتمال لوحة الإدارة — Al Takhfid

## حالة التنفيذ

هذه الوثيقة تصف حالة الفرع:
`feat/admin-completion-shein-ui-2026-09`

المرجع التشغيلي هو `main`، وتم إنشاء هذا الفرع منه مباشرة حتى تبقى نسخة الإنتاج الحالية منفصلة عن أعمال الإكمال.

## ما تم إكماله في هذه الموجة

### 1. تصميم الإدارة Mobile-First

- واجهة RTL تبدأ من شاشات الهاتف الصغيرة.
- Drawer على الهاتف وSidebar على الشاشات الكبيرة.
- Bottom Navigation مختصر للهاتف.
- بطاقات وأزرار بحجم لمس مريح.
- نظام ألوان قابل للتخصيص من قاعدة البيانات.
- اللون الافتراضي الجديد بنفس الروح البصرية للواجهة المرجعية: بنفسجي واضح مع أسطح بيضاء وخلفية فاتحة.
- Focus states واضحة للوحة المفاتيح ولمستخدمي إمكانية الوصول.
- تحسين hover/active/disabled وحواف البطاقات والظلال.
- منع التمدد الأفقي في الوحدات الإدارية.

### 2. محرر الترند المستطيل

المحرر يدعم:

`Hashtag → 3 Products → Background → Promo → Duration → Sort → Status`

ويطبق القواعد التالية:

- اختيار 3 منتجات بالضبط.
- المنتجات يجب أن تكون منشورة ومرتبطة بالهاشتاج المختار.
- ترتيب المنتجات محفوظ عبر `slot 0..2`.
- منع التكرار في قاعدة البيانات.
- الصورة الخلفية تمر عبر MediaService.
- المنتج المختار يظهر ببطاقة صغيرة ومحددة بصريًا.
- على الهاتف تظهر المنتجات الثلاثة في صف مضغوط، مع صورة مصغرة ونص مختصر.
- قائمة المنتجات المرشحة تصبح عمودين على الهاتف، مع حالة `selected` و`disabled`.
- البحث في المنتجات يعمل محليًا بعد جلب منتجات الهاشتاج.

### 3. أمان مسارات الإدارة

كان بعض مسارات الإدارة يمر بدون permission صريح.

تم تحويل طبقة حماية الصفحات إلى نموذج fail-closed:

- كل مسارات القائمة الإدارية لها permission واضح.
- GET يطلب صلاحية العرض أو الإدارة المناسبة.
- POST/التعديلات تطلب صلاحيات الإدارة.
- المسارات الديناميكية مثل المنتج والطلب والعميل لها قواعد prefix.
- أي مسار إداري مستقبلي لم تتم إضافته بعد إلى خريطة الصلاحيات يحتاج `system.manage` بدل المرور تلقائيًا.
- تسجيل الدخول وملفات static مستثناة بشكل صريح.

هذا لا يلغي الحاجة إلى مراجعة صلاحيات API الدقيقة في كل Domain، لكنه يغلق ثغرة المرور الافتراضي في صفحات الإدارة.

### 4. PWA وكاش لوحة الإدارة

ملفات static فقط تدخل الكاش.

صفحات الإدارة الموثقة/المصادقة لا يتم تخزين HTML الخاص بها في Service Worker.

الهدف:
- منع الاحتفاظ ببيانات إدارية قديمة في المتصفح.
- ضمان أن الصفحة الإدارية تأتي من الخادم.
- إبقاء الأصول الثابتة سريعة.

تم رفع إصدار الكاش إلى:

`altakhfidalsh-admin-v5`

## حالة الـCI

يجب أن يكون تعريف الإنجاز لكل موجة:

1. Compile.
2. PostgreSQL migration upgrade.
3. Migration current.
4. pytest.
5. مراجعة أخطاء runtime عند الحاجة.

في هذه الموجة أضيفت اختبارات تغطي:

- تغطية permissions لكل روابط Navigation.
- fail-closed للمسارات الإدارية المستقبلية.
- عدم كاش HTML الإداري في Service Worker.

## البنية الحالية للمتجر

### Catalog

- Products
- Categories recursive
- Brands
- Colors
- Sizes
- Options
- Variants
- Inventory
- Media
- Color-aware media
- Badges
- Hashtags
- Promotional strips
- Campaigns
- Shipping / Return / Warranty policies

### Storefront

- Pages
- Sections
- Items
- Banners
- Banner targets
- Category circles
- Hashtags
- Trends
- Campaigns
- Collections

### Commerce

- Cart
- Checkout primitives
- Orders
- Order status history
- Payments
- Payment proofs
- Shipping
- Shipments
- Tracking events

### Customer & Support

- OTP
- Customer
- Addresses
- Wishlist
- Recently viewed
- Notifications
- Conversations
- Messages
- Attachments

### After Sales & Loyalty

- Returns
- Refunds
- Warranty
- Reviews
- Coupons
- Gifts
- Wallet
- Wallet ledger

### System

- Admins
- Roles
- Permissions
- Audit logs
- Theme tokens
- Settings
- Feature flags

## ما يزال يحتاج موجة تنفيذ مستقلة

وجود model/API لا يعني أن شاشة الإدارة التشغيلية مكتملة.

### أولوية Catalog

- محرر فئات حقيقي مع نقل/إعادة ترتيب مرئي.
- Media Library كاملة: رفع متعدد، ترتيب، حذف، استبدال، معاينات.
- Variant Matrix عملية للمنتجات متعددة الألوان والمقاسات.
- Inventory locations ومخزون كل Variant.
- نشر المنتج مع checklist واضحة.

### أولوية Storefront

- محرر Pages/Sections/Items مرئي كامل.
- ترتيب drag/drop أو أدوات move up/down.
- Preview فعلي للصفحة قبل النشر.
- Banner target picker يعتمد على كيانات حقيقية.
- Category circles كأداة CRUD وليس قائمة عرض فقط.
- Collections قابلة للإنشاء والتعديل والترتيب.

### أولوية Operations

- مركز طلبات موحد.
- Workflow لحالات الطلب مع منع الانتقالات غير المسموحة.
- مراجعة إثباتات الدفع.
- إدارة الشحنات والتتبع.
- Returns/Refunds workflow.
- Warranty workflow.
- Review moderation.

### أولوية CRM

- Customer 360.
- بحث وفلاتر.
- عناوين.
- مجموعات التسعير للعميل.
- سجل الطلبات.
- المحادثة المرتبطة بالطلب.
- الإشعارات والقوالب.

### أولوية Reporting

- فلاتر زمنية.
- المدينة.
- العملة/مجموعة التسعير.
- حالة الطلب.
- المنتج/الفئة.
- مخزون.
- تصدير CSV/XLSX عند الحاجة.

## جاهزية تطبيق العميل

التطبيق العميل لا ينبغي أن يبدأ من صفحات ثابتة فقط.

العقد المناسب:

`Storefront API → Catalog API → Pricing API → Cart → Checkout → Orders → Customer → Support`

وتكون الصفحة الرئيسية تركيبًا من بيانات الإدارة:

`Page → Sections → Items`

وبالتالي يستطيع مدير المتجر تغيير ترتيب المحتوى دون إصدار تطبيق جديد، طالما بقي عقد API ثابتًا.

## قواعد التصميم المرجعية

التصميم المطلوب هو نمط متجر حديث كثيف المحتوى وليس نسخ HTML من متجر آخر:

- الصور هي العنصر البصري الأساسي.
- بطاقات المنتجات compact.
- عمودان للمنتجات على الهاتف عند ملاءمة المحتوى.
- بانرات عريضة.
- صفوف أفقية قابلة للتمرير.
- السعر والخصم واضحان.
- الشارات قصيرة.
- أزرار CTA بارزة.
- كل شاشة تدعم Loading/Empty/Error.
- كل وحدة تحفظ حالة الهاتف دون overflow.
- اللون والثيم قابلان للتعديل من الإدارة.

## قاعدة الإنجاز

لا تعتبر أي وحدة مكتملة لأن route موجود فقط.

Definition of Done:

`Model + Constraints + Migration + Service + API + Admin UI + Loading/Empty/Error + Permission + Audit عند الحاجة + Tests + Documentation`

## المرجع الحالي

- المشروع: `zydan25/altakhfidalsh`
- الفرع الأساسي: `main`
- فرع الإكمال: `feat/admin-completion-shein-ui-2026-09`
