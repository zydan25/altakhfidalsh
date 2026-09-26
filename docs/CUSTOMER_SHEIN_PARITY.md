# واجهة العميل — التخفيض الصح
## مرجع التنفيذ والمطابقة البصرية والوظيفية

> الهدف: بناء تطبيق العميل للمتجر ليحاكي تجربة SHEIN الحديثة في تدفق التسوق، مع هوية «التخفيض الصح» وبيانات المتجر الحالية.

## 1. النواتج
- Android APK عبر GitHub Actions.
- Flutter Web منشور تلقائيًا على GitHub Pages.
- RTL عربي ومتجاوب.
- المحتوى من الـAPI وليس بيانات تجريبية ثابتة.

## 2. مراجع تجربة الاستخدام
- https://m.shein.com/ar/
- https://m.shein.com/ar-en/
- https://ar.shein.com/

> المرجع يستخدم لتجربة الاستخدام والهندسة البصرية؛ الاسم والمواد والبيانات تخص «التخفيض الصح».

## 3. خريطة الشاشات

### الدخول
- الهاتف
- OTP
- حفظ الجلسة

### Shop / الرئيسية
1. رأس ثابت.
2. بحث سريع.
3. فئات جذرية قابلة للتمرير.
4. Banner قابل للنقر.
5. مزايا/شحن.
6. دوائر فئات.
7. Trend.
8. Looks.
9. شبكة منتجات.

### Category
- مركز الفئات.
- صفحة فئة.
- FilterSheet.
- شبكة ثنائية الأعمدة.
- تفاصيل المنتج.

### Search
- بحث مباشر.
- نتائج الشبكة.

### Product
- معرض صور.
- الاسم والسعر والخصم.
- Variants.
- Wishlist.
- إضافة للسلة.
- شراء الآن.
- الوصف والثقة.

### Cart
- العناصر.
- الكميات.
- الحذف.
- الإجمالي.
- CTA للدفع.

### Checkout
- عنوان الشحن.
- مراجعة الإجمالي.
- إنشاء الطلب.
- نجاح الطلب.

### Orders
- قائمة.
- التفاصيل.
- الشحن والتتبع.

### Me
- الملف.
- الطلبات.
- المفضلة.
- العناوين.
- الإشعارات.
- الدعم.
- Looks.
- تسجيل الخروج.

## 4. المطابقة البصرية الحالية
- Header أبيض وأيقونات بحث/مفضلة/سلة/رسائل.
- Search مستطيل فاتح صغير.
- Root tabs بتمرير أفقي وحالة نشطة.
- Banner PageView مع مؤشر.
- دوائر فئات وصور قادمة من الإدارة.
- Product grid ثنائي الأعمدة وصور طويلة.
- خصم وسعر سابق وسعر حالي.
- CTA سفلي في السلة/الدفع.
- Bottom navigation: Shop / Category / Trends / Cart / Me.

## 5. Design tokens
- الصفحة: 8–12 px margins.
- فجوات الشبكة: 2–6 px.
- نسبة صورة المنتج: ~0.79.
- البحث: ~42 px.
- Bottom bar: ~64 px.
- العناوين: 16–20 px.
- الوصف: 10–12 px.
- CTA: 48–50 px.
- أبيض/أسود/رمادي فاتح مع لون ترويجي محدود.

## 6. API
- /storefront/home
- /catalog/categories
- /catalog/products/feed
- /catalog/products/<id>
- /customer/auth/request-otp
- /customer/auth/verify-otp
- /customer/me
- /commerce/me/cart
- /commerce/me/cart/items
- /commerce/orders
- /commerce/me/orders
- /commerce/me/orders/<id>/detail
- /customer/me/addresses
- /customer/me/wishlist
- /support/conversations
- /support/conversations/<id>/messages

## 7. مصادر المحتوى
- Category: parent_id / icon_url.
- Banner: Banner + BannerTarget + assets.
- Looks: Look + cover + products.
- Trends: storefront payload.
- Product: Product + active Variant + media.

## 8. Android CI
` .github/workflows/client-ci.yml `
1. Checkout
2. Flutter stable
3. Android runner
4. pub get
5. analyze
6. test
7. release APK

## 9. GitHub Pages
` .github/workflows/client-pages.yml `
1. Web runner.
2. pub get.
3. flutter build web.
4. base href ديناميكي.
5. upload artifact.
6. deploy-pages.

العنوان المعتاد:
`https://<owner>.github.io/<repository>/`

## 10. آخر حالة تحقق قبل هذا التوثيق
- Flutter Analyze: SUCCESS.
- Flutter Test: SUCCESS.
- Flutter Release APK: SUCCESS.
- Backend CI: SUCCESS.

## 11. المرحلة التالية
1. Pixel tuning للـHome.
2. Category tabs/filter/sort.
3. Product gallery/variants/sticky CTA.
4. Cart coupons/summary.
5. Checkout shipping/payment/review.
6. Account/Orders/Support polish.
7. Smoke tests Android/Web.
8. Responsive rules موحدة.

## 12. قاعدة التنفيذ
كل شاشة جديدة يجب أن تستخدم API أو حالة محلية مبررة، RTL، design tokens، حالات loading/empty/error، وأن تبقى Android/Web قابلة للبناء.
