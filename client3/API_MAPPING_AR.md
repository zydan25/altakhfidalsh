# خريطة ربط TStore مع Flask — client3

> هذه خريطة أولية؛ لا تعني أن المسارات اختُبرت أو أن التطبيق مرتبط بالخادم بالفعل.

## الإعداد
- عنوان API المتوقع: `https://takhfidsh.alattab.site/api/v1`.
- يمرر العنوان من إعداد مركزي عبر `--dart-define=API_BASE_URL=...`.
- المسارات المحمية تستخدم `Authorization: Bearer <access_token>` وفق عقد Flask.
- شكل الخطأ الموثق: JSON يحوي `error` و`detail`، ويجب اختباره عملياً.

## خريطة أولية

| النطاق | مرجع من عقد المشروع | عمل المحوّل | الحالة |
|---|---|---|---|
| الصحة | `GET /health` و`GET /api/v1/health` | فحص الاتصال | يحتاج اختباراً |
| التصنيفات | `GET /catalog/categories`؛ يظهر أيضاً `/catalog/categories/tree` في بعض التوثيق | تحويل الشجرة و`parent_id` والترتيب | حسم المسار من Flask |
| المنتجات والبحث | `GET /catalog/products` و`GET /search/products?q=...` | ProductAdapter للمعرف والاسم والوصف والصور والسعر | مطابقة JSON مطلوبة |
| تفاصيل المنتج | `GET /catalog/products/{id}` | الخيارات والمتغيرات والألوان والمقاسات والمخزون | مطابقة JSON مطلوبة |
| الرئيسية والبنرات | `GET /storefront/pages`، `GET /storefront/pages/{code}`، `GET /storefront/banners` | تحويل الأقسام والعناصر والأهداف | التحقق من التنفيذ |
| التسعير | `GET /pricing/context`، `POST /pricing/quote`، `GET /pricing/currencies` | عرض السعر/العملة من الخادم دون حساب محلي | يحتاج اختباراً |
| OTP | `POST /customer/auth/request-otp` و`POST /customer/auth/verify-otp` | استبدال Supabase Auth | يحتاج اختباراً |
| الجلسة والحساب | `POST /customer/auth/refresh`، `POST /customer/auth/logout`، `GET /customer/me`، `PATCH /customer/me` | جلسة موحدة وملف العميل | يحتاج اختباراً |
| العناوين والمفضلة | `/customer/me/addresses` و`/customer/me/wishlist` | مزامنة بيانات العميل | يحتاج اختباراً |
| السلة | العقد الأساسي يوثق `GET /commerce/cart/{customer_id}` و`POST /commerce/cart/items`؛ توثيق client2 يذكر مسارات `/commerce/me/cart` | عدم اختيار مسار نهائي قبل مراجعة Flask | تعارض يحتاج حسم |
| الطلبات | العقد الأساسي يوثق `GET/POST /commerce/orders` و`GET /commerce/orders/{id}`؛ توثيق client2 يذكر `/commerce/me/orders` | ربط المستخدم والسعر والمخزون واللقطة التاريخية | تعارض يحتاج حسم |
| الشحن والدفع | `GET /commerce/shipping-methods`، `GET /commerce/payment-methods` ومسارات الدفع والشحن في العقد | عرض ما يقدمه الخادم فقط | يحتاج اختباراً |
| التقييمات | `GET /after_sales/reviews/product/{product_id}`، `POST /after_sales/reviews` | تحويل التقييم والتحقق من الصلاحيات | يحتاج اختباراً |
| المحادثات | `/support/conversations` و`/support/conversations/{id}/messages` ومرفقاتها | استخدام دعم Flask بدل Supabase Realtime | يحتاج اختباراً |
| الإشعارات | مسارات `/notifications` في العقد | قراءة الإشعارات وتسجيل رمز الجهاز بعد تحديد endpoint الدقيق | يحتاج تأكيداً |
| الكوبونات والحملات | `GET /promotions/campaigns`، `GET /promotions/coupons`، `POST /promotions/coupons/redeem` | ربط الخصومات التي يدعمها الخادم | يحتاج اختباراً |

## قواعد الربط
1. المرجع النهائي هو عقد `docs/API_CONTRACT_AR.md` ومسارات Flask المسجلة فعلياً في `app/`; لا يكفي وجود المسار في هذا الجدول.
2. تحسم الاختلافات بين توثيق API الرئيسي و`client2/API_MAPPING_AR.md` عن طريق فحص routes واختبار الاستجابات.
3. السعر النهائي وقواعد العملة والزيادة والتقريب مصدرها خدمة التسعير في الخادم.
4. يربط اللون/المقاس بمعرّف المتغير الصحيح؛ لا تعتمد الواجهة على اسم النص فقط إن كان الخادم يتطلب ID.
5. لا تستخدم بيانات تجريبية لتجاوز endpoint مفقود. تسجل الفجوة ويحدد بديل صحيح أو يُترك الجزء غير مفعّل بوضوح.
