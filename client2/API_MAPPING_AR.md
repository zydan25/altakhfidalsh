# خريطة مواءمة API — client2

## نقاط الاتصال

- عنوان API الحالي: `https://takhfidsh.alattab.site/api/v1`
- المصادقة: `Authorization: Bearer <access_token>`
- تنسيق الطلب المعتاد: JSON؛ تحميل الصور/المرفقات يكون `multipart/form-data`.
- المرجع المحلي للعقد: `docs/API_CONTRACT_AR.md`
- ملاحظة: المسارات التالية هي نقاط مواءمة متاحة في خادم Flask، وليست ادعاءً بأن واجهات WooCommerce متوافقة معها مباشرة. يجب مطابقة بنية كل استجابة مع نموذج المصدر وإضافة محوّل عند الحاجة.

## خريطة الميزات

| ميزة واجهة المصدر | نقطة الربط في Flask | قرار المواءمة |
|---|---|---|
| Dynamic layout / home blocks عبر `mstore_flutter-keys` | `GET /storefront/home`، و`GET /storefront/banners`، و`GET /storefront/pages` | محوّل من بنية الصفحة/الأقسام إلى نماذج Blocks التي تتوقعها الواجهة؛ لا نغيّر الواجهة المرئية. |
| قوائم المنتجات عبر `mstore_flutter-products` | `GET /catalog/products/feed`، `GET /catalog/products`، `GET /search/products?q=...` | تطبيع الصور والأسعار والعملة والمخزون والتصنيفات والتقسيم إلى صفحات قبل تمريرها لنموذج المنتج. |
| تفاصيل المنتج وتنوعاته | `GET /catalog/products/{id}` | تحويل الخيارات والألوان/المقاسات والمخزون من نموذج Flask إلى النموذج الذي تستهلكه شاشة التفاصيل. |
| التصنيفات | `GET /catalog/categories` | الحفاظ على علاقات `parent_id` وترتيبها؛ الفئة الجذرية لا تملك `parent_id`. |
| تسجيل الدخول والمصادقة المعتمدة على WordPress cookies/password | `POST /customer/auth/request-otp`، `POST /customer/auth/verify-otp`، `GET /customer/me`، `POST /customer/auth/logout` | استخدام تدفق OTP ورمز Bearer، مع تخزين جلسة `client2` منفصلًا. لا ترسل مفاتيح WooCommerce إلى التطبيق. |
| بيانات العميل والعناوين | `GET/PATCH /customer/me`، `GET/POST /customer/me/addresses` | محوّل لحقول العنوان والمدينة والمنطقة، والتحقق من الحقول المطلوبة قبل الإرسال. |
| المفضلة | `GET /customer/me/wishlist` و`POST /customer/me/wishlist/{product_id}` | مزامنة IDs مع نموذج المصدر والمحافظة على حال الواجهة عند انقطاع الشبكة. |
| السلة | `GET /commerce/me/cart`، `POST /commerce/me/cart/items`، ومسارات إزالة/تعديل عناصر السلة | ربط معرف المتغير والكمية والخيارات المختارة، ثم تطبيع الإجماليات بالعملة الحالية. |
| Checkout والطلبات | `GET /commerce/shipping-methods`، `GET /commerce/payment-methods`، `POST /commerce/me/orders`، `GET /commerce/me/orders/{id}/detail` | استخدام وسائل الدفع والشحن التي يعيدها الخادم؛ لا نفترض أن إضافة Stripe/Paystack القديمة متوافقة تلقائيًا. |
| الإشعارات | `GET /notifications/notifications/{customer_id}`، ومسارات تسجيل/إلغاء رمز الدفع في وحدة العميل | تكييف payload والتنقل إلى الشاشة المناسبة؛ اختبار التسجيل والإذن على Android بصورة منفصلة. |
| المحادثات مع الإدارة | `GET /support/conversations`، `GET /support/conversations/{id}/messages`، `POST /support/conversations/{id}/messages`، ورفع المرفقات | دعم محادثات Flask بدلاً من الاعتماد على Firebase Firestore كمصدر بيانات للمحادثة. التحديث الفوري يحتاج التحقق من آلية realtime المتاحة. |
| تقييمات المنتجات | `GET /after_sales/reviews/product/{product_id}`، `POST /after_sales/reviews` | محوّل للتقييمات والصور حسب صلاحيات الخادم. |
| معلومات المتجر والسياسات والمواقع | `GET /system/store-info`، `GET /system/policies`، `GET /storefront/store-locations` | ربط القيم التي يدعمها الخادم فقط؛ إبقاء عناصر التصميم مع إخفاء/تعطيل الحالة غير المدعومة بصورة مناسبة. |

## ميزات لا يوجد لها مقابل مباشر مؤكّد بعد

- حسابات البائعين وواجهات إدارة المتجر/منتجات البائعين وواجهات Dokan/WCFM/WC Marketplace.
- WordPress Blog ومسارات المحتوى ومكوّنات WordPress الإضافية.
- Firebase Chat الحالي للمحادثة بين العميل والبائع، ومحرك إضافات المنتجات (Product Addons).
- تكاملات الدفع القديمة التي تعتمد على بوابات/جلسات WooCommerce.

هذه الميزات لا يجوز ربطها بنقاط قريبة بالاسم فقط. يجب اختيار أحد المسارات: تنفيذ عقد Flask لها، أو توفير بديل مدعوم، أو تعطيل وظائفها غير المتاحة من دون كسر التنقل أو تغيير تصميم بقية التطبيق.

## قاعدة الحفاظ على التصميم

تبقى Widgets وملفات الصور والخطوط والثيمات كما هي بعد استيراد المصدر المرخّص. يبدأ التعديل في طبقات `ApiProvider` و`WooCommerceAPI` والموديلات/محوّلات JSON، ثم يُمسّ UI فقط إذا كشف اختبار عملي حاجة لا يمكن حلها داخل طبقة الربط.
