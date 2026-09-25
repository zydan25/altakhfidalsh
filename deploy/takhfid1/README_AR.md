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

sudo -E bash deploy/takhfid1/setup.sh

السكربت:
1. ينشئ قاعدة PostgreSQL باسم takhfid1 والمستخدم takhfid1 وكلمة المرور الافتراضية takhfid1 (ويمكن تجاوزها عبر TAKHFID1_DB_PASSWORD).
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

## سحب المشروع وتشغيله

من الخادم كـroot:

```bash
mkdir -p /home/root/projects
cd /home/root/projects
git clone --branch main --single-branch https://github.com/zydan25/altakhfidalsh.git takhfid1
cd /home/root/projects/takhfid1
sudo -E bash deploy/takhfid1/setup.sh
```

إذا كان المجلد موجودًا بالفعل، فالسكربت يسحب `main` ويعمل `reset --hard origin/main` قبل الإعداد. لا تضع `.env` أو مفاتيح WhatsApp في Git.

## DNS وNginx وSSL

اربط `takhfidsh.alattab.site` بعنوان الخادم. إعداد Nginx الموجود في `deploy/takhfid1/nginx/takhfidsh.alattab.site.conf` يوجه إلى `127.0.0.1:4006`.

بعد التأكد من نجاح HTTP:

```bash
certbot --nginx -d takhfidsh.alattab.site
nginx -t
systemctl reload nginx
curl -fsS https://takhfidsh.alattab.site/health
```

## PM2

اسم العملية `takhfid1`، وحالة التشغيل:

```bash
pm2 status
pm2 logs takhfid1 --lines 100
pm2 save
```

السكربت يحاول تفعيل `pm2-root` لإعادة الإحياء بعد إعادة تشغيل Ubuntu.