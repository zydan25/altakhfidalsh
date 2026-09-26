# حالة تنفيذ الفرع admin-first-foundation

## الهدف
بناء نواة متجر تجارة إلكترونية عربية RTL، Mobile-First، قابلة للتوسع إلى واجهة عميل PWA/Android لاحقًا، مع لوحة إدارة ERP Tree Navigation ومجالات بيانات منفصلة.

## مرجع التصميم
المرجع الأساسي هو تقرير بنية المتجر المستخلص من صور الواجهات. يعتمد النظام على:
- شجرة تصنيفات غير محدودة العمق.
- منتجات منفصلة عن الخيارات والمتغيرات والمخزون والوسائط.
- سعر أساسي موحد بالريال السعودي.
- محرك تسعير مركزي حسب أولوية العميل ثم المدينة ثم المنطقة ثم الافتراضي.
- لقطة تاريخية للتسعير داخل الطلب.
- Storefront ديناميكي قائم على pages/sections/items/targets.
- محادثات ومرفقات وضمان وإرجاع وتقييمات ومحافظ وكوبونات وهدايا وصلاحيات وتدقيق.

## نتيجة الفحص الحالي
- الفرع غير مدمج في main.
- النماذج الحالية تحتوي نواة واسعة جدًا وتغطي جداول التقرير، مع ثلاث جداول إضافية لتفصيل الشارات/الشرائط.
- توجد migrations محفوظة ومراجعة داخل `migrations/versions` حتى `20260926_0004_rectangular_trends.py`، وCI يطبقها على PostgreSQL نظيف.
- لوحة الإدارة تحتوي Navigation شجرية Mobile Drawer / Desktop Sidebar، لكن كان جزء من الحالة يُخزن في كائنات Navigation عالمية؛ تم فصل الحالة لتصبح request-scoped.
- الشارات في القائمة أصبحت تقرأ أعدادًا فعلية من قاعدة البيانات بدل الرقم 0 الثابت.
- عقد API أصبح يطابق prefixes الموثقة: /api/v1/<domain>/...
- السعر النهائي يستخدم Decimal على الخادم.
- الطلب يحفظ أيضًا effective markup percent/fixed في snapshot الرأس والعنصر.
- OTP أصبح متوافقًا مع قواعد timezone عند العمل مع SQLite/PostgreSQL.
- تعيين pricing group للموقع أصبح يتطلب مدينة أو منطقة واحدة فقط، مع CheckConstraint مانع للاثنين معًا.
- صفحة مجموعات التسعير أصبحت تدعم أكثر من قاعدة عملة للمجموعة، وربط المدينة/المنطقة، وتعيين مجموعة مباشرة للعميل مع percent/fixed overrides.
- صفحة البانرات أصبحت ترفع الصور بدل إدخال Asset IDs، وتستخدم MediaService لتحسين الصور، مع ربط الهدف بفئة/منتج/حملة/رابط.

## مبدأ التسعير
base_price_sar × fx_rate = converted
converted × percent_markup / 100 = percent_add
final = converted + percent_add + fixed_markup
ثم rounding حسب قاعدة المجموعة.

الأولوية:
1. customer_pricing_assignments
2. pricing_group_cities على مستوى المدينة
3. pricing_group_cities على مستوى المنطقة
4. pricing_groups.is_default

عند إنشاء الطلب تحفظ:
city_id + pricing_group_id + currency_id + fx_rate + markup_percent + markup_fixed + base_price_sar + sale_price_display.

## ما لا يعتبر مكتملًا بعد
- لا تزال migration الإنتاجية الابتدائية غير محفوظة.
- تم توسيع طبقة حماية صفحات الإدارة لتغلق المسارات غير المعروفة افتراضيًا، لكن بعض صفحات التشغيل المتقدمة ما زالت تحتاج CRUD تفاعلي كامل.
- إدارة الفئات تحتاج تحرير/حذف/إعادة ترتيب مرئي كامل وربط الصور والشارات.
- Product Wizard يحتاج استكمال عرض الوسائط الحقيقي، إدارة كل خصائص المنتج، وواجهة variant matrix أكثر قوة.
- Storefront يحتاج محرر صفحات/sections كاملًا مع ترتيب العناصر وقواعد الظهور.
- الدفع والشحن والإرجاع والضمان والمحادثة تحتاج إدارة تشغيلية كاملة من لوحة الإدارة.
- العملاء يحتاج البحث والتصفية وإدارة الحسابات والعناوين والتسعير من شاشة موحدة.
- التقارير تحتاج filters وتصدير ومؤشرات تشغيلية فعلية.
- Customer App / PWA يأتي بعد تثبيت نواة الإدارة وAPI.

## ترتيب التنفيذ التالي
### A — تثبيت قاعدة البيانات
1. إنشاء migration ابتدائية رسمية.
2. تشغيل migrate/upgrade من بيئة نظيفة.
3. منع schema drift في CI.
4. Seed آمن للعملات، SAR، الصلاحيات، الأدوار الأساسية.

### B — Catalog Administration
1. شجرة الفئات.
2. العلامات التجارية.
3. الألوان والمقاسات والخيارات.
4. Product Wizard الكامل.
5. variant matrix والمخزون.
6. الوسائط والشارات والسياسات.

### C — Storefront Administration
1. pages.
2. sections.
3. banners + targets.
4. category strip/circles.
5. campaigns/hashtags.
6. ترتيب المحتوى ومعاينته.

### D — Pricing
1. price trace لمستخدم/مدينة محددة.
2. إدارة أسعار الصرف المؤرخة.
3. إدارة قواعد العملات لكل group.
4. إدارة city/region/customer assignments.
5. اختبار snapshots عند تغير الصرف والمجموعة.

### E — Commerce & Operations
1. cart.
2. checkout.
3. payments/proofs.
4. shipping methods/rates/shipments.
5. order workflow/history.
6. chat/order conversation.

### F — After Sales & Loyalty
1. returns/refunds.
2. warranty claims.
3. reviews/media.
4. coupons.
5. gifts.
6. wallet ledger.
7. notifications.

### G — Security & Quality
1. permission audit لكل endpoint إداري.
2. audit_logs before/after.
3. request validation.
4. file validation/security.
5. API contract tests.
6. CI full pass.
7. performance/load review.

## قاعدة العمل
لا يتم اعتبار رابط إدارة موجودًا "مكتملًا" لمجرد أنه يعيد صفحة. Definition of Done لكل وحدة:
Model + constraints/indexes + migration + service + API + admin UI + loading/empty/error + permission + audit عند الحاجة + tests + documentation.
\n\n## موجة الإكمال الأخيرة\n\nتم توثيق تحسينات التصميم، حماية المسارات، أمان كاش لوحة الإدارة، ومحرر الترند المستطيل في `docs/ADMIN_COMPLETION_AR.md`.\n