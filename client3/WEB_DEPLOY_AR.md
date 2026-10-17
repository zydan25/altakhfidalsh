# معاينة client3 على الويب

سير عمل GitHub Pages موجود في `.github/workflows/client-pages.yml` ويبني المجلد `client3/` فقط. عند الدفع إلى `main` مع أي تغيير تحت `client3/**` يشغل الاختبارات والتحليل ثم بناء Flutter Web والنشر. يمكن أيضاً تشغيله يدوياً من تبويب Actions.

- مسار GitHub Pages: `https://zydan25.github.io/altakhfidalsh/`
- النطاق المخصص الذي يكتبه السير: `https://takhfidsh.alattab.site/`
- لا يحتاج معاينة الويب إلى بناء APK.
- قيمة `API_BASE_URL` تمرر وقت بناء الويب إلى `https://takhfidsh.alattab.site/api/v1`.
- هذه خطوة لنشر واجهة client3 للمعاينة. إلى أن تكتمل مراحل ربط المستودعات، توجد شاشات في المصدر ما زالت تعتمد على Supabase؛ لا تُفهم هذه المعاينة على أنها اكتمال تحويل البيانات إلى Flask.
