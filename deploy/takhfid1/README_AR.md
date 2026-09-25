# نشر takhfid1 على Ubuntu

هذه الحزمة تجهز المشروع في:

/home/root/projects/takhfid1

وتشغله عبر PM2 خلف Nginx على:

https://takhfidsh.alattab.site

المنفذ الداخلي للتطبيق:

127.0.0.1:4006

## المتطلبات

Python وPostgreSQL وNginx وNode.js وPM2 وGit موجودة مسبقًا حسب بيئة الخادم المطلوبة.

## التنفيذ

من داخل نسخة المشروع:

sudo bash deploy/takhfid1/setup.sh

السكربت:
1. ينشئ قاعدة PostgreSQL باسم takhfid1 والمستخدم takhfid1 وكلمة المرور takhfid1.
2. ينشئ البيئة الافتراضية ويثبت requirements.
3. يكتب .env الإنتاجي داخل المشروع.
4. يشغّل migrations وseed.
5. يجهز مجلد الوسائط.
6. ينسخ إعداد PM2 إلى /home/root/projects/takhfid1/ecosystem.config.cjs.
7. يثبت إعداد Nginx للنطاق.
8. يبدأ PM2 باسم takhfid1 ويشغّل الحفظ pm2 save.
9. يطبع أوامر certbot عند الحاجة.

## نقطة الاختبار

curl -fsS http://127.0.0.1:4006/health

بعد SSL:

curl -fsS https://takhfidsh.alattab.site/health

## WhatsApp

التكوين الافتراضي:
WHATSAPP_BASE_URL=https://whatsapp.alattab.site
WHATSAPP_SESSION=basheer

الـWebhook الذي يضبطه التكامل الخارجي هو:

https://takhfidsh.alattab.site/webhook/whatsapp
https://takhfidsh.alattab.site/webhook/session-status
https://takhfidsh.alattab.site/webhook/qr

وفق دليل WhatsApp الحالي، جلسة basheer تستخدم هذه المسارات عبر apiBaseUrl. fileciteturn368file0L563-L595

الإرسال من النظام يستخدم:
POST /api/sessions/basheer/send
multipart/form-data:
phoneNumber
message
media اختياري

وهذا مطابق للعقد الموثق في الدليل. fileciteturn368file0L230-L279

## أمان

لا تترك API الخاص بواتساب مكشوفًا للعامة دون حماية مناسبة. دليل التكامل الحالي يذكر صراحة غياب Authorization مخصص في الواجهة الحالية ويوصي بطبقة API Key/Bearer أو تقييد IP وHTTPS وrate limiting لمسار /send وعدم تسجيل QR في سجلات عامة. fileciteturn368file0L840-L849
