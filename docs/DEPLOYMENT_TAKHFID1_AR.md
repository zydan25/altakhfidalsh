# تشغيل takhfid1 على Ubuntu

المسار: /home/root/projects/takhfid1
المنفذ الداخلي: 127.0.0.1:4006
PM2: takhfid1
النطاق: https://takhfidsh.alattab.site
قاعدة البيانات: takhfid1
مستخدم قاعدة البيانات: takhfid1
كلمة مرور قاعدة البيانات لا تحفظ في Git؛ يمررها المشغل عبر TAKHFID1_DB_PASSWORD.

التنفيذ:
export TAKHFID1_DB_PASSWORD='YOUR_DB_PASSWORD'
sudo bash deploy/takhfid1/setup.sh

بعد النشر:
pm2 status
pm2 logs takhfid1 --lines 100
curl -fsS http://127.0.0.1:4006/health

SSL:
certbot --nginx -d takhfidsh.alattab.site

دخول المدير: الرقم المحلي 774952665 يطبّع إلى 967774952665، ويرسل OTP عبر WhatsApp. توجد كلمة مرور احتياطية.

التكامل يضبط جلسة basheer عبر https://whatsapp.alattab.site، وتعرض صفحة /admin/whatsapp الحالة وQR والرسائل والأخطاء والتنبيهات والإرسال.