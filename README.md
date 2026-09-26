# التخفيض - Al Takhfid AlSh

منصة تجارة إلكترونية عربية Mobile-First مبنية بـFlask وPostgreSQL، مع لوحة إدارة ERP Tree Navigation ثم تطبيق عميل PWA/Flutter في المراحل اللاحقة.

## الأساس المعماري
- Flask + Flask-SQLAlchemy + Flask-Migrate
- PostgreSQL
- REST API عبر Blueprints
- لوحة إدارة RTL Mobile-First
- محرك تسعير مركزي يعتمد على SAR كسعر أساس
- شجرة تصنيفات غير محدودة العمق
- Variants / Inventory / Media منفصلة عن هوية المنتج
- طلبات ودفع وشحن وإرجاع وضمان ومحادثات
- Pages / Sections / Banners / Campaigns / Hashtags
- صلاحيات وأدوار وAudit Log وثيم وFeature Flags

## المبدأ الأهم
السعر النهائي المعروض للعميل لا يخزن داخل المنتج كسعر ثابت بعملة العرض. يتم تحديد مجموعة التسعير حسب أولوية العميل ثم المدينة ثم المنطقة ثم الافتراضي، وبعدها يطبق سعر الصرف والزيادة والتقريب في خدمة واحدة باستخدام Decimal.
الطلبات تحفظ snapshots تاريخية للسعر والعملات والعنوان وخيارات المنتج حتى لا تتغير البيانات القديمة عند تعديل الكتالوج أو سعر الصرف.

## واجهة الإدارة
المسار: /admin/
- RTL بالكامل
- Sidebar ثابت على Desktop
- Drawer على الهاتف
- ERP Tree Navigation
- فتح تلقائي للقسم الذي يحتوي route الحالي
- حفظ حالة الأقسام في localStorage
- Responsive يبدأ من 360px

## API الحالية
- /health
- /api/v1/health
- /api/v1/categories/tree
- /api/v1/catalog/products
- /api/v1/pricing/preview

## التشغيل
استخدم Python 3.11.

    pip install -r requirements.txt

اضبط DATABASE_URL ثم:

    flask --app wsgi.py db migrate -m "initial ecommerce schema"
    flask --app wsgi.py db upgrade
    flask --app wsgi.py run

تشغيل الاختبارات:

    pytest

## التوثيق
- docs/IMPLEMENTATION_PLAN_AR.md
- docs/ADMIN_UI_SPEC_AR.md
- docs/DATABASE_DOMAINS_AR.md

## حالة المرحلة
هذا الفرع هو بداية البناء الإداري الحقيقي. الوحدات التي لم تكتمل بعد لها routes ومساحات أولية، لكنها لا تعتبر CRUD مكتملة حتى تمر بـmodel + migration + service + API/admin UI + permission + audit + tests.\n## الحالة الحالية\n\n- لوحة الإدارة RTL/Mobile-First مع ثيم قابل للتعديل.\n- محرر ترند مستطيل مرتبط بهاشتاج وثلاثة منتجات.\n- حماية صفحـات الإدارة مبنية على permissions مع fail-closed للمسارات الجديدة.\n- Service Worker يكاش الأصول الثابتة فقط ولا يحفظ HTML الإداري.\n- خطة إكمال الإدارة وتطبيق العميل موثقة في `docs/ADMIN_COMPLETION_AR.md`.\n