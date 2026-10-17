# خريطة API الفعلية لتطبيق client3

تاريخ التدقيق: 2026-10-17. هذا التدقيق مبني على تسجيل Blueprint ومسارات Flask في الشيفرة الحالية. لم أتعامل مع كل المسارات المذكورة في مستندات قديمة كأنها نشطة تلقائياً، ولم أغيّر الخادم أو قاعدة البيانات.

## قاعدة الاتصال

- الأصل الافتراضي: `https://takhfidsh.alattab.site/api/v1/` من `lib/core/network/api_config.dart`.
- كل المسارات في `lib/core/network/flask_endpoints.dart` نسبية ولا تبدأ بشرطة مائلة؛ هذا يحافظ على البادئة `/api/v1/` في Dio.
- التسجيل الفعلي في `app/__init__.py`: Blueprint الأساسي تحت `/api/v1` ثم Blueprints الوحدات تحت `/api/v1/<module>`.
- `app/api/__init__.py` يستورد `health` فقط. لذلك لا تُستخدم المسارات الموجودة في ملفات قديمة غير مستوردة مثل `app/api/catalog.py` أو `app/api/pricing.py` كعقد تشغيل فعلي. مثلاً لا نعتمد `/categories/tree` أو `/pricing/preview` من تلك الملفات.
- مسارات الوحدات أدناه هي المرجع الحالي؛ أي استجابة فعلية من الإنتاج تظل بحاجة إلى اختبار دخولي من بيئة تشغيل متصلة بالخادم.

## واجهات الكتالوج والواجهة الرئيسية

| الوظيفة | المسار الفعلي النسبي | الطريقة | الاستجابة/الحقول المثبتة في المصدر | ملاحظات العميل |
|---|---|---|---|---|
| بيانات الرئيسية المجمعة | `storefront/home` | GET | كائن يحوي `ui_settings`, `page`, `categories`, `category_display`, `side_categories`, `side_circle_display`, `side_circle_groups`, `trends`, `trend_hashtags`, `trend_settings`, `product_card_settings`, `looks`, `banners`, `coupon_strip` | هذا أفضل مدخل لجمع أقسام الرئيسية وإعداداتها. العناصر قد تكون فارغة إذا لم تُضبط في الإدارة. |
| قائمة الفئات | `catalog/categories` | GET | `{ "items": [...] }`; عنصر الفئة يتضمن `id`, `parent_id`, `name`, `slug`, `display_style`, `icon_asset_id`, `icon_url`, `badge_id`, `sort_order`, `is_active` | القائمة مسطحة، ابْنِ شجرة الفئات في التطبيق باستخدام `parent_id`. لا تفترض توفر endpoint شجرة مفعّل. |
| مجموعات الدوائر الجانبية | `catalog/side-circle-groups` | GET | `items`؛ يقبل `root_category_id` اختيارياً | تُقرأ الدوائر الجانبية منفصلة عن شجرة categories. |
| إعدادات الدوائر | `catalog/side-circle-display` | GET | `item` لإعدادات العرض | إعدادات عرض، وليست قائمة منتجات. |
| الفئات الجانبية ودوائرها | `catalog/side-categories` | GET | `items`؛ يقبل `root_category_id` اختيارياً. وقد يضم العنصر `circles` مع `image_url` والشارات | روابط الصور قد تكون نسبية ويجب حلّها من جذر المضيف باستخدام `ApiConfig.resolveMediaUrl`. |
| قائمة منتجات المتجر | `catalog/products/feed` | GET | `{ "items": [...] }`; بطاقة المنتج تحتوي على الأقل هوية/اسم/وصف وصور، وتضيف الواجهة `price`, `currency_code`, `compare_at_price`, `base_price_sar`, `available_qty`, `in_stock`, `badges`, `colors`, `rating`, `review_count`, `sold_qty`, `card_settings` عند توفر البيانات | هذه الواجهة مخصصة لبطاقات المتجر؛ لا تستخدم قيمة السعر المحلي أو سعر خام من واجهة البحث بدلاً منها. |
| تفاصيل المنتج | `catalog/products/{id}` | GET | `{ "item": ... }`; snapshot يضم المنتج وإعدادات التفاصيل والبطاقات والمقاسات/المتغيرات حسب بيانات المنتج | افحص `item` ثم مفاتيح snapshot داخله؛ لا تفترض أن جسم الاستجابة هو المنتج مباشرة. |
| منتجات دائرة | `catalog/side-category-circles/{id}/products` | GET | `items`، مبنية من serializer بطاقة المنتج | endpoint قائمة مستقل؛ يمكن استخدام feed إذا احتجت الفرز/التصفية الموحدة. |
| البحث النصي | `search/products?q=...` | GET | `items` مختصرة تتضمن `id`, `sku`, `name`, `base_price_sar`, `compare_at_price` | لا تعيد هذه الواجهة حقول الصور/السعر النهائي/العملة. لنتائج المتجر استخدم `catalog/products/feed?q=...` حتى تتطابق البطاقات مع تسعير الخادم. |
| البنرات | `storefront/banners` | GET | `items` | قد تقبل `root_category_id`؛ الحقول البصرية والأهداف تُحوّل من الاستجابة الفعلية. |
| صفحات المتجر | `storefront/pages` و`storefront/pages/{code}` | GET | قائمة `items`، وصفحة مفردة تتضمن `page` و`sections` وعناصرها | الرئيسية المجمعة متاحة من `storefront/home`. |

### معاملات feed المؤكدة في المصدر

`category_id`, `category_ids`, `circle_id`, `hashtag_id`, `hashtag_ids`, `side_category_id`, `q`, `currency_id`, `sort`, `discovery_tab`, `min_price`, `max_price`, `min_rating`, `filter_value_ids`, `limit`.

خيارات الفرز التي يتعامل معها المصدر صراحة: `price_asc`, `price_desc`, `newest`/`latest`, `popular`/`most_popular`/`best_selling`, `rating`/`rating_desc`/`highest_rated`, `random`/`shuffle`. القيمة الافتراضية هي التوصية المبنية على الأحدث. الحد الأعلى لـ`limit` هو 100 ولا تظهر في هذا المسار آلية صفحات `page/per_page`.

### التسعير والصور والمخزون

- `price` و`compare_at_price` من feed قيم نصية عشرية، و`currency_code` يحدد العملة المعروضة. هذه الأسعار محسوبة داخل خدمة Flask؛ لا تنفّذ التحويل أو الزيادة أو التقريب مرة ثانية داخل Flutter.
- قد يحتوي عنصر الصور على `url`, `color_id`, `width`, `height`. اترك الرابط المطلق كما هو، وحوّل الرابط النسبي من أصل المضيف وليس بإلحاقه بعد `/api/v1`.
- المصدر يضع قيمة SAR الأساسية في `price` كمسار احتياطي عند فشل استثناء التسعير. يجب ألا يفسّر العميل هذا الاحتياط كسعر عملة العميل إن كان `currency_code` يساوي SAR.
- `available_qty` و`in_stock` مصدرهما المخزون؛ لا تستنتج توفر المتغير من وجود اللون/المقاس فقط.

## العملة والحساب

| الوظيفة | المسار | الطريقة | الاستجابة |
|---|---|---|---|
| سياق السعر | `pricing/context` | GET | كائن مباشر: `pricing_group_id`, `pricing_group_name`, `currency_id`, `currency_code`, `source`, `percent_markup`, `fixed_markup`, `decimals`, `rounding_rule` |
| العملات النشطة | `pricing/currencies` | GET | `{ "items": [{id, code, symbol, name_ar, decimals, is_base}] }` |
| معاينة عرض سعر | `pricing/quote` | POST | `{ "item": ... }`; لمعاينة الإدارة/التحقق فقط، وليس بديل أسعار feed للعميل |

## المصادقة وحساب العميل

كل المسارات التالية تحت `/api/v1`:

| الوظيفة | المسار | الطريقة | الحماية/الملاحظة |
|---|---|---|---|
| طلب OTP | `customer/auth/request-otp` | POST | قبل الدخول؛ يعيد `item` مع مفاتيح من نتيجة الخدمة |
| تحقق OTP | `customer/auth/verify-otp` | POST | قبل الدخول؛ النتيجة داخل `item` |
| تجديد الجلسة | `customer/auth/refresh` | POST | يعتمد بيانات التجديد التي تقبلها الخدمة |
| خروج | `customer/auth/logout` | POST | استخدم الجلسة الحالية |
| جلب الحساب | `customer/me` | GET | Bearer token مطلوب |
| تعديل الحساب | `customer/me` | PATCH | Bearer token مطلوب |
| العناوين | `customer/me/addresses` | GET/POST | Bearer token؛ التعديل والحذف عبر `customer/me/addresses/{id}` |
| المفضلة | `customer/me/wishlist` | GET | الإضافة `POST customer/me/wishlist/{product_id}` والحذف DELETE للمسار نفسه |
| سجل المشاهدة | `customer/me/views/{product_id}` | POST | Bearer token مطلوب |

لا تزال أسماء مفاتيح token النهائية بحاجة إلى تثبيت باختبار استجابة OTP من بيئة تشغيل حقيقية قبل وصل التخزين الآمن واستعادة الجلسة.

## السلة والطلبات والشحن

| الوظيفة | المسار | الطريقة | ملاحظات |
|---|---|---|---|
| سلة العميل | `commerce/me/cart` | GET/DELETE | استخدم مسارات `me` حتى يستنتج الخادم صاحب السلة من الجلسة، ولا تمرر customer ID من الواجهة. |
| عناصر السلة | `commerce/me/cart/items` | POST | إضافة عنصر؛ التفاصيل يجب أن ترسل معرّف المتغير الفعلي والكمية بعد ربط المتغيرات. |
| تعديل عنصر | `commerce/me/cart/items/{item_id}` | PATCH/DELETE | تحديث كمية أو حذف عنصر. |
| قائمة الطلبات | `commerce/me/orders` | GET | Bearer token؛ تعيد `items`. |
| الطلب وتفاصيله | `commerce/me/orders/{id}`, `commerce/me/orders/{id}/detail` | GET | استخدم مسار العميل؛ لا تعتمد على معرف يختاره المستخدم للوصول إلى طلب عميل آخر. |
| إنشاء طلب | `commerce/orders` | POST | يحتاج اختبار payload والسعر/المخزون على الخادم قبل تفعيله. |
| طرق الشحن والدفع | `commerce/shipping-methods`, `commerce/payment-methods` | GET | اعرض الطرق التي يعيدها الخادم فقط. لا تفعّل دفعاً حقيقياً قبل تكامل واختبار مزود الدفع. |

## الأخطاء وحالات عدم اليقين

- الأخطاء المعتادة: JSON فيه `error` و/أو `detail`، لكن بعض المسارات تعيد خطأ بلا `detail`. على المحول استخدام حالة HTTP كمرجع إضافي.
- الاستجابات ليست كلها مغلفة بالطريقة نفسها: `items` للقوائم، `item` للعناصر المفردة، وكائن مباشر لبعض الواجهات مثل `storefront/home` و`pricing/context`.
- ملفات صور/رفع الوسائط لا تخلط مع مسارات JSON؛ المسارات التي ترفع ملفات تستخدم `multipart/form-data`.
- لا تُعدّل الخادم أو schema أو migrations في هذه المرحلة. النواقص المتعلقة بشكل بيانات مناسب للعميل تُعالج في محولات Flutter، وتُسجل كفجوة إذا لم يدعمها endpoint موجود.
- حالة التحقق: اكتمل تدقيق تسجيل المسارات وأشكال JSON الظاهرة من المصدر. لم يتم الادعاء بأن هذه الاستجابات اختبرت مباشرةً من الإنتاج؛ اختبار الدخان الحي للجلسة والكتالوج والأسعار ما زال مطلوباً من تشغيل يمكنه الوصول إلى الخادم.

## مراجع المصدر التي جرى تدقيقها

`app/__init__.py`, `app/api/__init__.py`, `app/modules/catalog/api.py`, `app/modules/catalog/services.py`, `app/modules/storefront/api.py`, `app/modules/search/api.py`, `app/modules/pricing/api.py`, `app/modules/customer/api.py`, `app/modules/commerce/api.py`.
