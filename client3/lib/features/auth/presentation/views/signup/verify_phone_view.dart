import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';
import 'package:t_store/core/enums/status.dart';
import 'package:t_store/core/common/widgets/navigation_menu.dart';
import 'package:t_store/core/cubits/navigation_menu_cubit/navigation_menu_cubit.dart';
import 'package:t_store/core/dependency_injection/service_locator.dart';
import 'package:t_store/core/utils/constants/image_strings.dart';
import 'package:t_store/core/utils/constants/sizes.dart';
import 'package:t_store/core/utils/device/device_utility.dart';
import 'package:t_store/core/utils/helpers/helper_functions.dart';
import 'package:t_store/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:t_store/features/auth/presentation/cubit/auth_state.dart';
import 'package:t_store/features/auth/presentation/views/login/login_view.dart';
import 'package:t_store/features/shop/presentation/controller/shop_cubit.dart';

class VerifyPhoneView extends StatefulWidget {
  const VerifyPhoneView({
    super.key,
    required this.phone,
    required this.otpRequestId,
  });

  final String phone;
  final int otpRequestId;

  @override
  State<VerifyPhoneView> createState() => _VerifyPhoneViewState();
}

class _VerifyPhoneViewState extends State<VerifyPhoneView> {
  final _codeController = TextEditingController();
  int _otpRequestId = 0;

  @override
  void initState() {
    super.initState();
    _otpRequestId = widget.otpRequestId;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _openStore() {
    THelperFunctions.navigateReplacementToScreen(
      context,
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => sl<NavigationMenuCubit>()),
          BlocProvider(
            create: (_) => sl<ShopCubit>()
              ..getSortedProducts(sortBy: 'rating', sortType: 'desc'),
          ),
        ],
        child: const NavigationMenu(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthOtpResent) {
          setState(() => _otpRequestId = state.otpRequestId);
          THelperFunctions.showSnackBar(
            context: context,
            message: 'أُرسل رمز تحقق جديد إلى ${state.phone}',
            type: SnackBarType.success,
          );
        } else if (state is AuthAuthenticated) {
          THelperFunctions.showSnackBar(
            context: context,
            message: 'تم إنشاء حسابك والتحقق من رقم الهاتف بنجاح.',
            type: SnackBarType.success,
          );
          _openStore();
        } else if (state is AuthError) {
          THelperFunctions.showSnackBar(
            context: context,
            message: state.message,
            type: SnackBarType.error,
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginView()),
                    (route) => false,
                  );
                },
                icon: const Icon(CupertinoIcons.clear),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(TSizes.defaultSpace),
                child: Column(
                  children: [
                    Image(
                      width: TDeviceUtils.getScreenWidth(context) * .6,
                      image: const AssetImage(
                        TImages.deliveredEmailIllustration,
                      ),
                    ),
                    const SizedBox(height: TSizes.spaceBtwSections),
                    Text(
                      'تحقق من رقم هاتفك',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: TSizes.spaceBtwItems),
                    Text(
                      'أدخل رمز التحقق المكوّن من 6 أرقام المرسل إلى',
                      style: Theme.of(context).textTheme.labelLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: TSizes.spaceBtwItems),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        widget.phone,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: TSizes.spaceBtwSections),
                    TextFormField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Iconsax.sms),
                        labelText: 'رمز التحقق',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: TSizes.spaceBtwSections),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                THelperFunctions.hideKeyboard();
                                context.read<AuthCubit>().verifyRegistrationOtp(
                                      otpRequestId: _otpRequestId,
                                      code: _codeController.text,
                                    );
                              },
                        child: isLoading
                            ? const Text('جارٍ التحقق...')
                            : const Text('تحقق وأنشئ الحساب'),
                      ),
                    ),
                    const SizedBox(height: TSizes.spaceBtwItems),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: isLoading
                            ? null
                            : () => context
                                .read<AuthCubit>()
                                .resendRegistrationOtp(),
                        child: const Text('إعادة إرسال رمز التحقق'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}
