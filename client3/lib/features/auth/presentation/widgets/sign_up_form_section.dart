import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';
import 'package:t_store/core/dependency_injection/service_locator.dart';
import 'package:t_store/core/network/flask_customer_api.dart';
import 'package:t_store/core/utils/constants/sizes.dart';
import 'package:t_store/core/utils/helpers/helper_functions.dart';
import 'package:t_store/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:t_store/features/auth/presentation/cubit/auth_state.dart';
import 'package:t_store/features/auth/presentation/views/signup/verify_phone_view.dart';
import 'package:t_store/features/auth/presentation/widgets/terms_and_privacy_agreement.dart';

class SignUpFormSection extends StatefulWidget {
  const SignUpFormSection({super.key});

  @override
  State<SignUpFormSection> createState() => _SignUpFormSectionState();
}

class _SignUpFormSectionState extends State<SignUpFormSection> {
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _loadingLookups = true;
  String? _lookupError;
  String? _gender;
  int? _selectedCityId;
  int? _selectedCurrencyId;
  List<FlaskLookupOption> _cities = const [];
  List<FlaskLookupOption> _currencies = const [];

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRegistrationOptions();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadRegistrationOptions() async {
    setState(() {
      _loadingLookups = true;
      _lookupError = null;
    });
    try {
      final api = sl<FlaskCustomerApi>();
      final results = await Future.wait([
        api.getCities(),
        api.getCurrencies(),
      ]);
      if (!mounted) return;
      final cities = results[0];
      final currencies = results[1];
      setState(() {
        _cities = cities;
        _currencies = currencies;
        if (_selectedCurrencyId == null && currencies.isNotEmpty) {
          _selectedCurrencyId = currencies
              .firstWhere(
                (item) => item.isDefault,
                orElse: () => currencies.first,
              )
              .id;
        }
        _lookupError = cities.isEmpty
            ? 'لا توجد مدن متاحة من الخادم حاليًا.'
            : currencies.isEmpty
                ? 'لا توجد عملات متاحة من الخادم حاليًا.'
                : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lookupError = 'تعذر تحميل المدن والعملات من الخادم. أعد المحاولة.';
      });
    } finally {
      if (mounted) setState(() => _loadingLookups = false);
    }
  }

  void _handleRegistration() {
    if (!_formKey.currentState!.validate()) return;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    context.read<AuthCubit>().requestRegistrationOtp(
      phone: _phoneController.text.trim(),
      registration: <String, dynamic>{
        'name': '$firstName $lastName',
        'gender': _gender,
        'city_id': _selectedCityId,
        'preferred_currency_id': _selectedCurrencyId,
        'password': _passwordController.text,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthOtpRequired) {
          final cubit = context.read<AuthCubit>();
          THelperFunctions.showSnackBar(
            context: context,
            message: 'تم إرسال رمز التحقق إلى ${state.phone}',
            type: SnackBarType.success,
          );
          THelperFunctions.navigateReplacementToScreen(
            context,
            BlocProvider.value(
              value: cubit,
              child: VerifyPhoneView(
                phone: state.phone,
                otpRequestId: state.otpRequestId,
              ),
            ),
          );
        } else if (state is AuthError) {
          THelperFunctions.showSnackBar(
            context: context,
            message: state.message,
            type: SnackBarType.error,
          );
        }
      },
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    textInputAction: TextInputAction.next,
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? 'أدخل الاسم الأول.'
                        : null,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Iconsax.user),
                      labelText: 'الاسم الأول',
                    ),
                  ),
                ),
                const SizedBox(width: TSizes.spaceBtwInputFields),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    textInputAction: TextInputAction.next,
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? 'أدخل اسم العائلة.'
                        : null,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Iconsax.user),
                      labelText: 'اسم العائلة',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TSizes.spaceBtwInputFields),
            DropdownButtonFormField<String>(
              value: _gender,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Iconsax.user_edit),
                labelText: 'الجنس',
              ),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('ذكر')),
                DropdownMenuItem(value: 'female', child: Text('أنثى')),
              ],
              onChanged: (value) => setState(() => _gender = value),
              validator: (value) => value == null ? 'اختر الجنس.' : null,
            ),
            const SizedBox(height: TSizes.spaceBtwInputFields),
            DropdownButtonFormField<int>(
              value: _selectedCurrencyId,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Iconsax.wallet),
                labelText: 'العملة المفضلة',
              ),
              items: _currencies
                  .map((currency) => DropdownMenuItem<int>(
                        value: currency.id,
                        child: Text(currency.label, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _loadingLookups || _currencies.isEmpty
                  ? null
                  : (value) => setState(() => _selectedCurrencyId = value),
              validator: (value) =>
                  value == null ? 'اختر العملة من القائمة.' : null,
            ),
            const SizedBox(height: TSizes.spaceBtwInputFields),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              textDirection: TextDirection.ltr,
              validator: (value) {
                final phone = value?.trim() ?? '';
                final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
                return digits.length < 7 ? 'أدخل رقم هاتف صحيحًا.' : null;
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Iconsax.call),
                labelText: 'رقم الهاتف',
              ),
            ),
            const SizedBox(height: TSizes.spaceBtwInputFields),
            DropdownButtonFormField<int>(
              value: _selectedCityId,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Iconsax.location),
                labelText: 'المدينة',
              ),
              items: _cities
                  .map((city) => DropdownMenuItem<int>(
                        value: city.id,
                        child: Text(city.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _loadingLookups || _cities.isEmpty
                  ? null
                  : (value) => setState(() => _selectedCityId = value),
              validator: (value) => value == null ? 'اختر المدينة.' : null,
            ),
            if (_loadingLookups) ...[
              const SizedBox(height: TSizes.spaceBtwItems),
              const LinearProgressIndicator(),
            ],
            if (_lookupError != null) ...[
              const SizedBox(height: TSizes.spaceBtwItems),
              Text(
                _lookupError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _loadingLookups ? null : _loadRegistrationOptions,
                child: const Text('إعادة تحميل البيانات'),
              ),
            ],
            const SizedBox(height: TSizes.spaceBtwInputFields),
            TextFormField(
              controller: _passwordController,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              validator: (value) => (value ?? '').length < 6
                  ? 'كلمة المرور يجب أن تتكون من 6 أحرف على الأقل.'
                  : null,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                prefixIcon: const Icon(Iconsax.password_check),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Iconsax.eye_slash : Iconsax.eye),
                  onPressed: () => setState(() {
                    _obscurePassword = !_obscurePassword;
                  }),
                ),
                labelText: 'كلمة المرور',
              ),
            ),
            const SizedBox(height: TSizes.spaceBtwInputFields),
            TextFormField(
              controller: _confirmPasswordController,
              keyboardType: TextInputType.visiblePassword,
              validator: (value) => value != _passwordController.text
                  ? 'كلمتا المرور غير متطابقتين.'
                  : null,
              obscureText: _obscurePassword,
              decoration: const InputDecoration(
                prefixIcon: Icon(Iconsax.password_check),
                labelText: 'تأكيد كلمة المرور',
              ),
            ),
            const SizedBox(height: TSizes.spaceBtwInputFields),
            const TermsAndPrivacyAgreement(),
            const SizedBox(height: TSizes.spaceBtwSections),
            SizedBox(
              width: double.infinity,
              child: BlocBuilder<AuthCubit, AuthState>(
                builder: (context, state) {
                  return ElevatedButton(
                    onPressed: state is AuthLoading || _loadingLookups
                        ? null
                        : () {
                            THelperFunctions.hideKeyboard();
                            _handleRegistration();
                          },
                    child: state is AuthLoading
                        ? const Text('جارٍ إنشاء الحساب...')
                        : const Text('إنشاء حساب'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
