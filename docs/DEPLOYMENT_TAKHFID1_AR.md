# تشغيل وتحديث takhfid1 على Ubuntu

المسار:
`/home/root/projects/takhfid1`

المنفذ الداخلي الفعلي:
`127.0.0.1:4008`

PM2:
`takhfid1`

النطاق:
`https://takhfidsh.alattab.site`

قاعدة البيانات:
`takhfid1`

مستخدم قاعدة البيانات:
`takhfid1`

كلمة مرور قاعدة البيانات لا تحفظ في Git؛ يمررها المشغل عبر
`TAKHFID1_DB_PASSWORD` عند تنفيذ سكربت الإعداد الأولي.

## التثبيت الأولي

```bash
cd /home/root/projects/takhfid1
export TAKHFID1_DB_PASSWORD='YOUR_DB_PASSWORD'
sudo bash deploy/takhfid1/setup.sh
```

سكربت الإعداد ينشئ البيئة الافتراضية داخل:

```
/home/root/projects/takhfid1/.venv
```

ويثبت الاعتمادات ويطبق migrations وينشئ/يضبط PM2 وNginx.

## تحديث نسخة موجودة

لا تستخدم `pip` الخاص بالنظام ولا تنفذ `flask db migrate` على خادم الإنتاج عند نشر migrations موجودة في Git.

```bash
cd /home/root/projects/takhfid1

git fetch origin
git reset --hard origin/main

source .venv/bin/activate
python -m pip install -r requirements.txt

flask db current
flask db upgrade
flask db current

python -m compileall app tests
pytest

pm2 restart takhfid1
pm2 status
pm2 logs takhfid1 --lines 100

curl -fsS http://127.0.0.1:4008/health
```

إذا لم توجد `.venv` في نسخة قديمة من المشروع، أنشئها أولًا باستخدام Python 3.11 المتوافق مع CI:

```bash
cd /home/root/projects/takhfid1
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

ثم طبّق:

```bash
flask db upgrade
```

## قاعدة migrations

الـmigrations الملتزم بها حاليًا موجودة داخل:

`migrations/versions/`

ولا تُنشئ revision جديدة على الإنتاج لمجرد تحديث الكود. أنشئ migration جديدة أثناء التطوير عندما يتغير الـschema، راجعها واختبرها، ثم ارفعها إلى Git. على الخادم طبّق الموجود باستخدام:

```bash
flask db upgrade
```

## التحقق بعد التحديث

يجب أن تكون حالة migration على آخر head، ويجب أن ينجح الاختبار:

```bash
flask db current
pytest
```

ويجب أن يستجيب التطبيق:

```bash
curl -fsS http://127.0.0.1:4008/health
```

## SSL

```bash
certbot --nginx -d takhfidsh.alattab.site
```

## الإدارة وواتساب

دخول المدير يستخدم الرقم المحلي `774952665` الذي يطبّع إلى `967774952665`، ويرسل OTP عبر WhatsApp، مع كلمة مرور احتياطية.

تكامل WhatsApp يستخدم الجلسة:

`basheer`

والواجهة متاحة داخل:

`/admin/whatsapp`

