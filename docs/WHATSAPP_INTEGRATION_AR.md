# تكامل WhatsApp داخل takhfid1

الجلسة: basheer
Base URL: https://whatsapp.alattab.site/api/sessions/basheer

الدليل المرفوع يحدد status وQR وconnect وdisconnect وlogout وsend وmessages وerrors وnotifications. fileciteturn368file0L24-L36

الإرسال يستخدم multipart/form-data مع phoneNumber وmessage وmedia الاختياري. fileciteturn368file0L230-L279

Webhook الرسائل والحالة وQR يعتمد على apiBaseUrl، والمسارات هي /webhook/whatsapp و/webhook/session-status و/webhook/qr. fileciteturn368file0L504-L559

صفحة الإدارة: /admin/whatsapp

الأمان: الدليل يوصي بطبقة Authorization أو API Gateway، HTTPS، تقييد IP، rate limiting لمسار send وعدم تسجيل QR. fileciteturn368file0L840-L849