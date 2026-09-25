# نشر takhfid1 على Ubuntu

هذه الحزمة تنشر المشروع في:

`/home/root/projects/takhfid1`

وتشغله عبر PM2 باسم:

`takhfid1`

على المنفذ الداخلي:

`127.0.0.1:4006`

والنطاق:

`takhfidsh.alattab.site`

## التنفيذ الموصى به

لا تحتاج إلى إنشاء مجلد جديد إذا كان المشروع موجودًا.

بعد سحب `main` إلى الخادم:

```bash
cd /home/root/projects/takhfid1
git fetch origin main
git checkout -B main origin/main
git reset --hard origin/main
chmod +x deploy/takhfid1/deploy.sh
bash deploy/takhfid1/deploy.sh
```

أو يمكن تشغيله من أي مكان بعد سحب المشروع:

```bash
cd /home/root/projects/takhfid1
bash deploy/takhfid1/deploy.sh
```

سيطلب السكربت منك:

```text
WHATSAPP_API_KEY
```

ثم يحفظه داخل:

```text
/home/root/projects/takhfid1/.env
```

ولا يطبعه في الشاشة.

## ماذا ينفذ deploy.sh

السكربت الواحد يقوم بالخطوات التالية:

1. يستخدم المجلد الموجود `/home/root/projects/takhfid1` إن كان موجودًا.
2. يسحب `main` من GitHub ويجعل نسخة الخادم مطابقة له بدون حذف الملفات غير المتتبعة مثل `.env` والوسائط.
3. ينشئ أو يحدث Python virtualenv ويثبت `requirements.txt`.
4. ينشئ قاعدة PostgreSQL باسم `takhfid1` والمستخدم `takhfid1`.
5. يجهز `.env` ويحدّث قيم الإنتاج وWhatsApp فعليًا حتى لو كان `.env` موجودًا مسبقًا.
6. يولد تلقائيًا `SECRET_KEY` وكلمة مرور الإدارة و`WHATSAPP_WEBHOOK_SECRET` عند عدم وجودها في متغيرات البيئة.
7. يشغل `flask db upgrade` و`scripts/seed.py`.
8. يثبت إعداد PM2 باسم `takhfid1` على المنفذ `4006`.
9. يثبت إعداد Nginx للنطاق `takhfidsh.alattab.site`.
10. يعيد تشغيل PM2 ويحاول تفعيل `pm2-root` للإقلاع بعد إعادة تشغيل الخادم.
11. يفحص `/health` محليًا وينتظر حتى يصبح التطبيق جاهزًا.
12. يحاول تفعيل SSL تلقائيًا بواسطة Certbot إذا كان DNS للنطاق محلولًا وCertbot مثبتًا.

## WhatsApp

القيم الافتراضية:

```env
WHATSAPP_BASE_URL=https://whatsapp.alattab.site
WHATSAPP_SESSION=basheer
WHATSAPP_TIMEOUT=20
WHATSAPP_EXTERNAL_URL=https://takhfidsh.alattab.site
```

ويتم وضع:

```env
WHATSAPP_API_KEY=<المفتاح الذي تدخله أثناء النشر>
WHATSAPP_WEBHOOK_SECRET=<يولد تلقائيًا>
```

داخل `.env`.

مسارات الـWebhook المستخدمة من المشروع:

```text
https://takhfidsh.alattab.site/webhook/whatsapp
https://takhfidsh.alattab.site/webhook/session-status
https://takhfidsh.alattab.site/webhook/qr
```

ولوحة WhatsApp:

```text
https://takhfidsh.alattab.site/admin/whatsapp
```

## Nginx

الإعداد موجود في:

```text
deploy/takhfid1/nginx/takhfidsh.alattab.site.conf
```

ويوجه الطلبات إلى:

```text
127.0.0.1:4006
```

ويخدم الوسائط من:

```text
/home/root/projects/takhfid1/storage/media/
```

## SSL

إذا كان:

```text
takhfidsh.alattab.site
```

يشير عبر DNS إلى عنوان الخادم، والـCertbot مثبت، فإن `deploy.sh` يحاول تنفيذ SSL تلقائيًا.

إذا تم تجاوز SSL أو فشل بسبب DNS، نفذ بعد تصحيح DNS:

```bash
certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d takhfidsh.alattab.site --redirect
nginx -t
systemctl reload nginx
```

## التحقق

بعد النشر:

```bash
cd /home/root/projects/takhfid1
bash deploy/takhfid1/verify.sh
```

أو:

```bash
pm2 status
pm2 logs takhfid1 --lines 100
curl -fsS http://127.0.0.1:4006/health
```

وبعد SSL:

```bash
curl -fsS https://takhfidsh.alattab.site/health
```

## التحديثات اللاحقة

بعد دمج أي تغيير في `main`:

```bash
cd /home/root/projects/takhfid1
bash deploy/takhfid1/update.sh
```

## ملاحظات مهمة

لا تضع `.env` أو `WHATSAPP_API_KEY` داخل Git.

كلمة مرور PostgreSQL الافتراضية في حزمة النشر هي `takhfid1` ويمكن تغييرها قبل التشغيل عبر:

```bash
export TAKHFID1_DB_PASSWORD='كلمة_مرور_أقوى'
bash deploy/takhfid1/deploy.sh
```
