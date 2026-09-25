# مواصفة واجهة الإدارة

## الهدف

لوحة إدارة عربية RTL تشبه أدوات ERP الحديثة، وليست Dashboard Cards ولا نسخة Desktop مصغرة.

## Navigation

- Sidebar ثابت على Desktop.
- Drawer على الهاتف.
- أقسام رئيسية قابلة للفتح والإغلاق.
- Children متداخلة داخل Container منفصل.
- Chevron يتغير حسب الحالة.
- Active route يفتح parent تلقائيًا.
- حفظ حالة الأقسام في localStorage.
- تمرير داخلي للقائمة.
- لا حذف لأي عنصر Navigation عند إضافة وحدات جديدة.

## Mobile-First

الاختبارات المرجعية:
- 360×800
- 390×844
- 412×915

القواعد:
- Safe Area.
- Responsive دون عرض ثابت يخرج من الشاشة.
- أزرار وتفاعل 44-48px على الأقل.
- نماذج كبيرة وسهلة بيد واحدة.
- لا ازدحام.
- لا اعتماد على hover.

## المكونات

المكونات المشتركة يجب أن تدعم:
- default
- pressed
- focused
- disabled
- loading
- empty
- error
- success feedback

## الثيم

الثيم يعتمد على:
- primary
- accent
- background
- surface
- text
- muted
- danger
- success
- price
- discount

مع Theme Tokens وقواعد للمكونات.

## معيار جاهزية الشاشة

قبل اعتبار شاشة الإدارة جاهزة:
- ترتيب الهاتف محدد.
- مكونات قابلة لإعادة الاستخدام محددة.
- مصادر البيانات واضحة.
- route وpermission معروفان.
- إجراءات الحفظ والإلغاء واضحة.
- الخطأ يظهر قريبًا من الحقل.
- لا توجد عناصر صغيرة يصعب لمسها.
