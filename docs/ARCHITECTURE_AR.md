# معمارية نظام التخفيض

## الطبقات

HTTP/Blueprint
→ Schema/validation
→ Domain Service
→ Repository/SQLAlchemy
→ PostgreSQL

الخدمات المشتركة:
- pricing
- audit
- phone
- media

## الوحدات

app/modules/
- catalog
- pricing
- storefront
- commerce
- customer
- support
- promotions
- geo
- after_sales
- notifications
- reports
- search
- system

هذا هو الأسلوب المكافئ لفكرة Django Apps مع بقاء الخادم Flask.

## قاعدة البيانات

المصدر الحالي للـschema هو app/models.py حتى لا تتكرر تعريفات Foreign Key بين الوحدات.
تم تثبيت أكثر من 100 جدول Domain، مع فصل product identity عن options/variants/media/inventory.

## Storefront

StorefrontPage
→ StorefrontSection
→ StorefrontSectionItem
→ target entity

Banner
→ BannerTarget

هذا يسمح ببناء الرئيسية من بيانات، بدل HTML ثابت.

## Pricing

CustomerAssignment
→ City Assignment
→ Region Assignment
→ Default Group

ثم rule + FX + rounding.

## Orders

Cart
→ Order
→ OrderItem snapshot
→ Payment / Shipment / Status history

Order snapshot مستقل عن التغيير اللاحق في المنتج أو FX أو مجموعة التسعير.

## Media

الملفات لا تحفظ كـBLOB افتراضيًا.
MediaAsset يحتفظ بالـmetadata.
الصور تمر عبر Pillow وتتحول إلى WebP مع تحديد أقصى ضلع وجودة قابلة للتهيئة.

## Security

- OTP hashed + expiry + attempts.
- access/refresh token hashes.
- Flask admin session.
- roles / permissions.
- audit log before/after.
- secure cookie configuration.

## UI

Admin:
Mobile-First RTL + ERP Tree + PWA shell.

Customer:
سيبنى لاحقًا فوق API مستقرة وبنفس responsive contract، وليس العكس.

## قواعد التطور

أي Domain جديد يجب أن يحتوي:
- API contract.
- service.
- model/migration.
- tests.
- permission عند الحاجة.
- audit للحركات الحساسة.
- documentation.

لا يتم وضع منطق التسعير أو الطلب في Flutter.
