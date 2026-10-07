import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'shein_ui.dart';
import 'theme.dart';
import 'widgets.dart';
import 'notifications_service.dart';
import 'referral_links.dart';

class SxWelcomeScreen extends StatefulWidget {
  const SxWelcomeScreen({super.key});
  @override
  State<SxWelcomeScreen> createState() => _SxWelcomeScreenState();
}

class _SxWelcomeScreenState extends State<SxWelcomeScreen> {
  bool accepted = false;
  bool loading = true;
  String privacy = 'نستخدم بياناتك لتسجيل الحساب وإدارة الطلبات والتوصيل والدعم، ونحافظ عليها وفق سياسة الخصوصية المعتمدة في المتجر.';

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final data = await api.policies();
      final item = data['privacy'];
      if (item is Map && (item['body'] ?? '').toString().trim().isNotEmpty) {
        privacy = item['body'].toString();
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> continueFlow() async {
    if (!accepted) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool('welcome_seen_v1', true);
    try { await api.acceptPrivacy(); } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SxAuthFlowScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 42, 22, 28),
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(22)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 24),
                  const Text('مرحبًا بك في التخفيض الصح', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  const Text(
                    'متجرك لاكتشاف المنتجات والعروض وإتمام الطلب بسهولة، مع تجربة عربية سريعة من هاتفك.',
                    style: TextStyle(fontSize: 12, color: ClientTheme.muted, height: 1.7),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: ClientTheme.soft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ClientTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.privacy_tip_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('قبل أن نبدأ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (loading) const LinearProgressIndicator(minHeight: 2),
                        if (!loading) Text(privacy, style: const TextStyle(fontSize: 10, color: ClientTheme.muted, height: 1.6)),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: accepted,
                          onChanged: (v) => setState(() => accepted = v == true),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'أوافق على سياسة الخصوصية واستخدام بياناتي لتشغيل المتجر والطلبات.',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: accepted ? continueFlow : null,
                      style: FilledButton.styleFrom(backgroundColor: Colors.black),
                      child: const Text('ابدأ الآن', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'التخفيض الصح · تجربة تسوق عربية متكاملة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: ClientTheme.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SxAuthFlowScreen extends StatefulWidget {
  const SxAuthFlowScreen({super.key});
  @override
  State<SxAuthFlowScreen> createState() => _SxAuthFlowScreenState();
}

class _SxAuthFlowScreenState extends State<SxAuthFlowScreen> {
  final phone = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  final fullName = TextEditingController();
  final district = TextEditingController();
  final street = TextEditingController();
  final landmark = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();

  String mode = 'phone';
  String gender = '';
  String? error;
  bool busy = false;
  int? otpRequestId;
  String? normalizedPhone;
  String? existingCustomerName;

  List<Map<String, dynamic>> cities = [];
  List<Map<String, dynamic>> areas = [];
  List<Map<String, dynamic>> currencies = [];
  int? cityId;
  int? areaId;
  int? currencyId;
  String currencySymbol = 'ر.س';

  @override
  void initState() { super.initState(); loadReferences(); }

  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    code.dispose();
    fullName.dispose();
    district.dispose();
    street.dispose();
    landmark.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> loadReferences() async {
    try {
      final result = await Future.wait<dynamic>([api.cities(), api.currencies()]);
      if (!mounted) return;
      setState(() {
        cities = (result[0] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
        currencies = (result[1] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
        if (currencies.isNotEmpty) {
          currencyId = int.tryParse((currencies.first['id'] ?? '').toString());
          currencySymbol = (currencies.first['symbol'] ?? currencies.first['code'] ?? 'ر.س').toString();
        }
      });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
  }

  Future<void> loadAreas(int id) async {
    setState(() { cityId = id; areaId = null; areas = []; });
    try {
      final rows = await api.cityAreas(cityId: id);
      if (!mounted) return;
      setState(() {
        areas = rows;
        if (areas.length == 1) areaId = int.tryParse((areas.first['id'] ?? '').toString());
      });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
  }

  void fail(Object e) {
    if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
  }

  Future<void> submitPhone() async {
    final value = phone.text.trim();
    if (value.isEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      final result = await api.checkPhone(value);
      normalizedPhone = (result['phone'] ?? value).toString();
      final exists = result['exists'] == true;
      existingCustomerName = (result['name'] ?? '').toString().trim();
      if (existingCustomerName!.isEmpty) existingCustomerName = null;

      if (!exists) {
        // Only a genuinely new phone number can enter the registration form.
        if (mounted) setState(() => mode = 'register');
        return;
      }

      // Existing customers always start with the password screen.
      // Legacy accounts without a password can use "نسيت كلمة المرور"
      // to establish a password through phone verification.
      if (mounted) setState(() => mode = 'existing_password');
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loginPassword() async {
    setState(() { busy = true; error = null; });
    try {
      await api.passwordLogin(normalizedPhone ?? phone.text.trim(), password.text);
      await finalizeLogin();
    } catch (e) { fail(e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> startRegistration() async {
    if (fullName.text.trim().length < 2 || gender.isEmpty || cityId == null || currencyId == null ||
        newPassword.text.length < 6 || newPassword.text != confirmPassword.text) {
      fail('أكمل الاسم والجنس والمدينة والعملة وكلمة المرور وتأكيدها.');
      return;
    }
    if (areas.isNotEmpty && areaId == null) { fail('اختر المنطقة داخل المدينة.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final r = await api.requestOtp(normalizedPhone ?? phone.text.trim(), purpose: 'register');
      otpRequestId = int.tryParse((r['otp_request_id'] ?? '').toString());
      setState(() => mode = 'otp_register');
    } catch (e) { fail(e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> verifyRegistration() async {
    setState(() { busy = true; error = null; });
    try {
      await api.verifyOtp(
        otpRequestId!,
        code.text.trim(),
        phone: normalizedPhone,
        registration: {
          'name': fullName.text.trim(),
          'gender': gender,
          'city_id': cityId,
          'city_area_id': areaId,
          'district': district.text.trim(),
          'street': street.text.trim(),
          'landmark': landmark.text.trim(),
          'preferred_currency_id': currencyId,
          'password': newPassword.text,
        },
      );

      // The account is now authenticated. Give a brand-new customer one
      // optional referral step; existing accounts never see this step.
      await finalizeLogin(redirectToHome: false);
      final referralCode = await ReferralLinkService.takePendingCode();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SxReferralOnboardingScreen(initialCode: referralCode),
        ),
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SxAppShell()),
        (_) => false,
      );
    } catch (e) { fail(e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> verifyLoginOtp() async {
    setState(() { busy = true; error = null; });
    try {
      await api.verifyOtp(otpRequestId!, code.text.trim(), phone: normalizedPhone);
      await finalizeLogin();
    } catch (e) { fail(e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> requestReset() async {
    setState(() { busy = true; error = null; });
    try {
      final r = await api.passwordResetRequest(normalizedPhone ?? phone.text.trim());
      otpRequestId = int.tryParse((r['otp_request_id'] ?? '').toString());
      setState(() => mode = 'reset_password');
    } catch (e) { fail(e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> resetPassword() async {
    if (otpRequestId == null || code.text.trim().length < 4 ||
        newPassword.text.length < 6 || newPassword.text != confirmPassword.text) {
      fail('أدخل كود التحقق وكلمة مرور جديدة متطابقة.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await api.passwordReset(otpRequestId!, code.text.trim(), newPassword.text);
      await api.passwordLogin(normalizedPhone ?? phone.text.trim(), newPassword.text);
      await finalizeLogin();
    } catch (e) { fail(e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> finalizeLogin({bool redirectToHome = true}) async {
    try { await api.acceptPrivacy(); } catch (_) {}
    await state.restorePreferences();

    final notificationsGranted =
        await AltakhfidNotificationService.requestNotificationAccess();

    if (!notificationsGranted && mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(
            'فعّل إشعارات التخفيض الصح',
            textAlign: TextAlign.right,
          ),
          content: const Text(
            'حتى تصلك رسائل الطلبات والمحادثات وتغييرات حالة الدفع والشحن فورًا، اسمح للتطبيق بالإشعارات. ولظهورها كنافذة منبثقة أعلى الشاشة، تأكد من تفعيل «إظهار كنافذة منبثقة» ضمن إعدادات إشعارات التطبيق.',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ليس الآن'),
            ),
            FilledButton(
              onPressed: () async {
                await AltakhfidNotificationService.openNotificationSettings();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('فتح إعدادات الإشعارات'),
            ),
          ],
        ),
      );
    }

    await AltakhfidNotificationService.ensureStarted();
    if (!redirectToHome || !mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SxAppShell()),
      (_) => false,
    );
  }

  InputDecoration deco(
    String label, {
    IconData? icon,
    bool ltr = false,
  }) =>
      InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        alignLabelWithHint: true,
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        prefixIcon: icon == null ? null : Icon(icon, size: 20, color: ClientTheme.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E2E2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E2E2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1.3),
        ),
        labelStyle: const TextStyle(
          fontSize: 11,
          color: Color(0xFF777777),
          fontWeight: FontWeight.w600,
        ),
      );

  Widget tf(
    TextEditingController c,
    String label, {
    bool obscure = false,
    TextInputType? type,
    IconData? icon,
    bool ltr = false,
  }) =>
      TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
        textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
        textAlign: ltr ? TextAlign.left : TextAlign.right,
        textAlignVertical: TextAlignVertical.center,
        scrollPadding: const EdgeInsets.only(bottom: 180),
        autocorrect: type == null || type == TextInputType.text,
        enableSuggestions: !obscure,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        decoration: deco(label, icon: icon, ltr: ltr),
      );

  Widget dropdown(String label, int? value, List<Map<String, dynamic>> rows, ValueChanged<int?> onChanged, {String Function(Map<String,dynamic>)? labelBuilder}) {
    return DropdownButtonFormField<int>(
      value: value,
      isExpanded: true,
      decoration: deco(label),
      items: rows.map((x) {
        final id = int.tryParse((x['id'] ?? '').toString());
        return DropdownMenuItem<int>(
          value: id,
          child: Text(labelBuilder == null ? (x['name'] ?? x['code'] ?? '').toString() : labelBuilder(x)),
        );
      }).where((x) => x.value != null).toList(),
      onChanged: onChanged,
    );
  }

  Widget action(String label, VoidCallback? cb) => SizedBox(
    height: 50,
    child: FilledButton(
      onPressed: busy ? null : cb,
      style: FilledButton.styleFrom(backgroundColor: Colors.black),
      child: busy ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    ),
  );

  Widget header(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('التخفيض الصح', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(fontSize: 10, color: ClientTheme.muted, height: 1.55)),
      if (error != null) ...[
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: const Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(8)),
          child: Text(error!, style: const TextStyle(fontSize: 9.5, color: Color(0xFFC62828))),
        ),
      ],
      const SizedBox(height: 14),
    ],
  );

  Widget locationFields() => Column(
    children: [
      dropdown('المدينة', cityId, cities, (id) { if (id != null) loadAreas(id); }),
      if (cityId != null && areas.isNotEmpty) ...[
        const SizedBox(height: 9),
        dropdown('المنطقة', areaId, areas, (id) => setState(() => areaId = id)),
      ],
      const SizedBox(height: 9),
      tf(district, 'الحي'),
      const SizedBox(height: 9),
      tf(street, 'الشارع'),
      const SizedBox(height: 9),
      tf(landmark, 'علامة مميزة'),
    ],
  );

  Widget genderFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('الجنس', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(child: ChoiceChip(label: const Text('ذكر'), selected: gender == 'male', onSelected: (_) => setState(() => gender = 'male'))),
          const SizedBox(width: 7),
          Expanded(child: ChoiceChip(label: const Text('أنثى'), selected: gender == 'female', onSelected: (_) => setState(() => gender = 'female'))),
        ],
      ),
    ],
  );

  Widget registerForm() => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(14, 30, 14, 120),
    children: [
      header('مرحبًا بك لأول مرة', 'نحتاج بيانات بسيطة لتجهيز حسابك والطلبات والتوصيل.'),
      tf(fullName, 'الاسم الكامل'),
      const SizedBox(height: 10),
      genderFields(),
      const SizedBox(height: 10),
      locationFields(),
      const SizedBox(height: 10),
      dropdown(
        'العملة',
        currencyId,
        currencies,
        (id) {
          final match = currencies.where((x) => int.tryParse((x['id'] ?? '').toString()) == id);
          setState(() {
            currencyId = id;
            if (match.isNotEmpty) currencySymbol = (match.first['symbol'] ?? match.first['code'] ?? currencySymbol).toString();
          });
        },
        labelBuilder: (x) => (x['name_ar'] ?? x['code'] ?? '').toString() + ' · ' + (x['symbol'] ?? x['code'] ?? '').toString(),
      ),
      const SizedBox(height: 10),
      tf(newPassword, 'كلمة المرور', obscure: true),
      const SizedBox(height: 10),
      tf(confirmPassword, 'تأكيد كلمة المرور', obscure: true, icon: Icons.lock_outline),
      const SizedBox(height: 14),
      action('متابعة والتحقق من الرقم', startRegistration),
      const SxDeveloperSignature(),
    ],
  );

  Widget passwordLogin() => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(14, 42, 14, 120),
    children: [
      header(
        existingCustomerName == null || existingCustomerName!.isEmpty
            ? 'مرحبًا بعودتك'
            : 'مرحبًا بعودتك، $existingCustomerName',
        'هذا حسابك الحالي. أدخل كلمة المرور للمتابعة، أو استخدم «نسيت كلمة المرور» لاستعادتها عبر رقم الهاتف.',
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.phone_outlined, size: 18, color: ClientTheme.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(normalizedPhone ?? phone.text.trim(), textDirection: TextDirection.ltr, textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
        ]),
      ),
      const SizedBox(height: 12),
      tf(password, 'كلمة المرور', obscure: true, icon: Icons.lock_outline),
      const SizedBox(height: 11),
      action('دخول', loginPassword),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : requestReset,
              child: const Text('نسيت كلمة المرور', style: TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
      TextButton(onPressed: busy ? null : () => setState(() => mode = 'phone'), child: const Text('تغيير الرقم')),
      const SxDeveloperSignature(),
    ],
  );

  Widget phoneForm() => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(16, 44, 16, 120),
    children: [
      header('ابدأ برقم جوالك', 'سنتحقق هل لديك حساب سابق أم تحتاج إلى تسجيل جديد.'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE7E7E7)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: Colors.black,
                  child: Icon(Icons.phone_iphone_outlined, color: Colors.white, size: 19),
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'رقم الهاتف',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            tf(
              phone,
              'مثال: 7XXXXXXXX',
              type: TextInputType.phone,
              icon: Icons.phone_outlined,
              ltr: true,
            ),
            const SizedBox(height: 12),
            action('متابعة', submitPhone),
            const SizedBox(height: 8),
            const Text(
              'سيرسل رمز التحقق عبر WhatsApp عند الحاجة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 8.5, color: ClientTheme.muted, height: 1.45),
            ),
          ],
        ),
      ),
      const SxDeveloperSignature(),
    ],
  );

  Widget otpForm(bool registration) => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(14, 50, 14, 120),
    children: [
      header(registration ? 'تحقق من رقمك' : 'الدخول بكود التحقق', 'أدخل الكود الذي وصل إلى الرقم ' + (normalizedPhone ?? phone.text.trim()) + '.'),
      tf(code, 'كود التحقق', type: TextInputType.number, ltr: true),
      const SizedBox(height: 12),
      action(registration ? 'تأكيد وإنشاء الحساب' : 'تأكيد الدخول', registration ? verifyRegistration : verifyLoginOtp),
      TextButton(
        onPressed: busy ? null : () => setState(() => mode = registration ? 'register' : 'phone'),
        child: const Text('تغيير الرقم'),
      ),
      const SxDeveloperSignature(),
    ],
  );

  Widget resetForm() => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(14, 50, 14, 120),
    children: [
      header('استعادة كلمة المرور', 'أرسلنا لك رمز تحقق جديدًا لتعيين كلمة مرور جديدة.'),
      tf(code, 'كود التحقق', type: TextInputType.number),
      const SizedBox(height: 10),
      tf(newPassword, 'كلمة المرور الجديدة', obscure: true, icon: Icons.lock_reset_outlined),
      const SizedBox(height: 10),
      tf(confirmPassword, 'تأكيد كلمة المرور', obscure: true),
      const SizedBox(height: 12),
      action('حفظ والدخول', resetPassword),
      TextButton(onPressed: busy ? null : () => setState(() => mode = 'existing_password'), child: const Text('العودة للدخول')),
      const SxDeveloperSignature(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (mode) {
      case 'existing_password': body = passwordLogin(); break;
      case 'existing_otp': body = otpForm(false); break;
      case 'register': body = registerForm(); break;
      case 'otp_register': body = otpForm(true); break;
      case 'otp_login': body = otpForm(false); break;
      case 'reset_password': body = resetForm(); break;
      default: body = phoneForm();
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
