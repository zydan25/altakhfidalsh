# مخطط تنفيذ نظام التخفيض

## 1. المرجع

هذا المستودع يبني منصة تجارة إلكترونية عربية قابلة للتوسع، مستوحاة من نمط المتاجر الحديثة شبيه SHEIN، مع أولوية حقيقية للهاتف في الواجهة الإدارية ثم واجهة العميل.

المرجع الوظيفي الأساسي هو تقرير تحليل الصور المرفق، الذي فصل الكتالوج، شجرة التصنيفات، المحتوى، التسعير، الطلبات، المحادثات، الإرجاع، الضمان، المحافظ، الصلاحيات والتدقيق إلى نطاقات مترابطة.

## 2. القرار المعماري

- Flask + Flask-SQLAlchemy + Flask-Migrate.
- PostgreSQL هو مخزن البيانات الرئيسي.
- Blueprint مستقل لكل نطاق API والإدارة.
- السعر الأساسي للمنتج محفوظ بالريال السعودي SAR.
- السعر النهائي لا يكتب داخل المنتج كعملة عرض؛ يحسب في خدمة تسعير مركزية.
- أولوية مجموعة التسعير: تعيين العميل ثم المدينة ثم المنطقة ثم المجموعة الافتراضية.
- الحساب المالي على الخادم باستخدام Decimal.
- الطلب يحفظ snapshots للسعر والصرف والمجموعة والعملة والعنوان.
- الصور والملفات تمر عبر MediaAsset بدل تخزينها كـBLOB داخل الجداول.
- التعديلات الإدارية الحساسة ستسجل في AuditLog.

## 3. النواة التي تم تنفيذها في هذا الفرع

تم توسيع نموذج البيانات ليشمل:
- الدول والمناطق والمدن والعملات وأسعار الصرف.
- مجموعات التسعير وقواعدها وربطها بالمدن والعملاء.
- العملاء والعناوين والأجهزة وOTP والجلسات والتفضيلات.
- الوسائط والعلامات التجارية والألوان والمقاسات.
- شجرة التصنيفات ذات العمق غير المحدود.
- خيارات المنتج وOption Values وVariants وصور الـVariant والمخزون.
- سياسات الشحن والإرجاع والضمان والشارات.
- الوسوم والهاشتاجات والحملات والبنرات وصفحات المتجر وأقسامه.
- السلة والمفضلة والطلبات وسجل الحالات.
- الشحن والتتبع والدفع وإثباتات الدفع.
- المحادثات والرسائل والمرفقات.
- الإرجاع والاسترداد والضمان والتقييمات.
- الكوبونات والهدايا والمحافظ ودفتر حركات المحفظة.
- الإشعارات.
- المدراء والأدوار والصلاحيات والتدقيق.
- الثيمات وTheme Tokens وإعدادات المكونات والميزات والإعدادات ومرادفات البحث.

## 4. واجهة الإدارة الحالية

- RTL بالكامل.
- تصميم يبدأ من 360px.
- Sidebar ثابت على الشاشات الكبيرة.
- Drawer على الهاتف.
- ERP Tree Navigation بأقسام قابلة للفتح والإغلاق.
- القسم النشط يفتح تلقائيًا.
- العنصر الحالي Active واضح.
- حفظ حالة فتح الأقسام في localStorage.
- مناطق تفاعل لا تقل عن 44-48px تقريبًا.
- حالات Empty/Error كنمط تصميم للوحدات القادمة.
- لا يوجد Desktop Layout مصغر للهاتف.

الأقسام الإدارية الحالية:
الرئيسية، الكتالوج، المحتوى والمتجر، التسعير، المبيعات والطلبات، العملاء والتواصل، الترويج والمالية، النظام.

## 5. مبدأ ديناميكية النظام

- الفئات تتفرع بلا حد، وتستخدم نفس العقدة كفئة دائرية أو شريط أو فلتر.
- البانر له target مستقل.
- الصفحات تتكون من sections، والـsection من items مرتبة.
- الحملة تربط منتجات وتصنيفات وهاشتاجات.
- الشارات كيان مستقل يعاد استخدامه.
- الثيم يعتمد على tokens بدل hard-coded colors.
- المزايا تتحكم فيها Feature Flags.
- القائمة الإدارية تنتقل لاحقًا إلى صلاحيات وبيانات عند اكتمال طبقة الأمان مع الاحتفاظ بـfallback واضح.

## 6. طريقة التسعير

converted = base_price_sar × fx_rate

percent_add = converted × percent_markup / 100

final = converted + percent_add + fixed_markup

ثم يطبق rounding المحدد داخل قاعدة المجموعة.

## 7. ترتيب السبرنتات

### Sprint 01 — Foundation
- [x] Flask factory
- [x] Extensions
- [x] Domain model foundation
- [x] Pricing service
- [x] Admin blueprint
- [x] Mobile-first ERP navigation
- [x] Catalog category tree API
- [x] Basic product listing API
- [x] Domain modules: catalog/pricing/storefront/commerce/customer/support/promotions/geo/after_sales/notifications/reports/search/system
- [x] Product filter definitions and product filter values
- [x] Customer bearer access + refresh rotation
- [x] Admin API permission decorator
- [ ] Initial Alembic revision generated against PostgreSQL
- [ ] CI test workflow

### Sprint 02 — Admin Catalog (قيد التوسعة)
- [x] Product CRUD
- [ ] Side-category circle assignment UX refinements
- [ ] Product wizard متعدد الخطوات
- [ ] Media upload + Pillow optimization
- [ ] Colors / sizes / options / variants
- [ ] Inventory
- [ ] Category tree CRUD and drag ordering
- [ ] Badges and product display settings
- [ ] Shipping/return/warranty assignment

### Sprint 03 — Admin Storefront
- [ ] Storefront pages
- [ ] Sections and items
- [ ] Banner CRUD + targets
- [ ] Category circles
- [x] Hashtags and trends
- [x] Independent side categories and circular merchandising
- [ ] Campaign builder
- [ ] New / offers / bestseller collections

### Sprint 04 — Pricing & Geo
- [ ] Countries / regions / cities UI
- [ ] Currency UI
- [ ] Exchange-rate UI
- [ ] Pricing groups UI
- [ ] City/region assignments
- [ ] Customer override UI
- [ ] Price simulator with trace explaining the applied rule

### Sprint 05 — Orders
- [ ] Cart
- [ ] Checkout
- [ ] Order creation
- [ ] Payment methods
- [ ] Manual proof upload
- [ ] Shipments and tracking
- [ ] Status transition rules
- [ ] Historical snapshots

### Sprint 06 — Customer & Support
- [ ] OTP
- [ ] Customer profile
- [ ] Addresses
- [ ] Wishlist
- [ ] Notifications
- [ ] Conversations
- [ ] Attachments
- [ ] Order-linked chat

### Sprint 07 — Returns / Warranty / Reviews
- [ ] Return request workflow
- [ ] Refund ledger
- [ ] Warranty claim workflow
- [ ] Review moderation
- [ ] Review media

### Sprint 08 — Promotions & Wallet
- [ ] Coupons
- [ ] Gifts
- [ ] Wallet
- [ ] Wallet ledger
- [ ] Automatic promotion rules

### Sprint 09 — Security & Admin
- [ ] Admin authentication
- [ ] Roles
- [ ] Fine-grained permissions
- [ ] Audit logs
- [ ] Feature flags
- [ ] Theme management
- [ ] App settings

### Sprint 10 — Reports / QA / Performance
- [ ] Sales reports
- [ ] Product and inventory reports
- [ ] Customer reports
- [ ] Pricing audit report
- [ ] Integration tests
- [ ] PostgreSQL query/index review
- [ ] Media optimization
- [ ] Production CI/CD

## 8. قواعد تمنع التضخم والفوضى

- لا نضع اللون والمقاس والصور داخل products كأعمدة متكررة.
- لا نخزن سعر YER أو عملة عميل داخل product كسعر نهائي دائم.
- لا نربط البانر بفئة عن طريق اسم نصي.
- لا نحول الشارات والتخفيضات إلى HTML داخل اسم المنتج.
- لا نعيد حساب الطلبات التاريخية من المنتج الحالي.
- لا نخزن OTP أو refresh token كنص صريح.
- لا نخزن ملفات الصور كـBLOB داخل PostgreSQL افتراضيًا.
- لا تجعل كل شاشة تحسب السعر بنفسها؛ service واحدة فقط.

## 9. تعريف الإنجاز

لا تعتبر الوحدة مكتملة إلا عندما يكون لها:
1. Model / migration.
2. Service/domain logic.
3. API route أو admin route واضح.
4. واجهة Mobile-First عند الحاجة.
5. حالات Loading/Empty/Error.
6. صلاحية مناسبة.
7. Audit عند العملية الحساسة.
8. Test للحالة الأساسية.
9. توثيق للزر ومصدر بياناته.

## 10. الخطوة التالية

الأولوية العملية التالية هي Product CRUD الكامل من لوحة الإدارة، لأن معالج إضافة المنتج هو أكثر جزء كثافة في الصور، ولأنه سيختبر العلاقات بين الصور والخيارات والـVariants والمخزون والفئات والسياسات والشارات والتسعير قبل الانتقال إلى تطبيق العميل.


## 11. الحالة الحالية في الفرع

- 105 جداول SQLAlchemy للنواة الموسعة.
- لوحة الإدارة PWA/ERP تعمل كهيكل Mobile-First.
- معالج المنتج متعدد الخطوات موجود ويكتب إلى قاعدة البيانات.
- التسعير حسب العميل/المدينة/المنطقة منفذ كخدمة مركزية.
- الطلب/السلة/الدفع/الشحن/ما بعد البيع/المحادثة لها خدمات وواجهات أساسية.
- البحث والفلاتر والهاشتاجات والحملات والواجهات الديناميكية لها Domains مستقلة.
- المهاجرات والبنية موجودة، بينما ملف migration الأول الفعلي سيُولد ويُراجع على PostgreSQL في بيئة CI/التشغيل قبل اعتماده للإنتاج.


## موجة 0005 — الفئات الجانبية ومؤقت الترند

- تمت إضافة مؤقت ترند بالثواني أو الدقائق مع `started_at/ends_at` في عقد API العام.
- تمت إضافة نص Overlay اختياري بألوان قابلة للإدارة.
- تمت إضافة `SideCategory → SideCategoryCircle → ProductSideCategoryCircle` كمنظومة مستقلة عن التصنيفات الأساسية.
- القسم الجانبي يقبل root category فقط، أي Category ذات `parent_id = NULL`.
- معالج المنتج أصبح يعرض دوائر الفئات الجانبية ويخزن روابط المنتج بها.
