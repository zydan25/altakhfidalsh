import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:t_store/core/network/flask_customer_api.dart';
import 'package:t_store/core/usecases/usecase.dart';
import 'package:t_store/features/auth/domain/usecases/sign_in_usecase.dart';
import 'package:t_store/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:t_store/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:t_store/features/auth/domain/usecases/reset_password_usecase.dart';
import 'package:t_store/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:t_store/features/auth/presentation/cubit/auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final SignInUsecase signInUsecase;
  final SignUpUsecase signUpUsecase;
  final SignOutUsecase signOutUsecase;
  final ResetPasswordUsecase resetPasswordUsecase;
  final GetCurrentUserUsecase getCurrentUserUsecase;
  final FlaskCustomerApi? customerApi;

  Map<String, dynamic>? _pendingRegistration;
  String? _pendingPhone;

  AuthCubit({
    required this.signInUsecase,
    required this.signUpUsecase,
    required this.signOutUsecase,
    required this.resetPasswordUsecase,
    required this.getCurrentUserUsecase,
    this.customerApi,
  }) : super(AuthInitial());

  Future<void> checkAuthStatus() async {
    emit(AuthLoading());
    final result = await getCurrentUserUsecase(const NoParams());
    result.fold(
      (error) => emit(AuthUnauthenticated()),
      (user) {
        if (user != null) {
          emit(AuthAuthenticated(user));
        } else {
          emit(AuthUnauthenticated());
        }
      },
    );
  }

  /// Customer password login now uses the phone number against Flask.
  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    final api = customerApi;
    if (api == null) {
      emit(const AuthError('خدمة تسجيل الدخول غير مهيأة.'));
      return;
    }

    emit(AuthLoading());
    try {
      final user = await api.loginWithPhone(phone: phone, password: password);
      emit(AuthAuthenticated(user));
    } catch (error) {
      emit(AuthError(_arabicAuthError(error)));
    }
  }

  /// Starts registration by requesting an OTP. The account is created by Flask
  /// only after the user submits the valid code.
  Future<void> requestRegistrationOtp({
    required String phone,
    required Map<String, dynamic> registration,
  }) async {
    final api = customerApi;
    if (api == null) {
      emit(const AuthError('خدمة إنشاء الحساب غير مهيأة.'));
      return;
    }

    emit(AuthLoading());
    try {
      final request = await api.requestOtp(phone: phone, purpose: 'register');
      _pendingPhone = request.phone;
      _pendingRegistration = Map<String, dynamic>.from(registration);
      emit(AuthOtpRequired(phone: request.phone, otpRequestId: request.id));
    } catch (error) {
      emit(AuthError(_arabicAuthError(error)));
    }
  }

  Future<void> resendRegistrationOtp() async {
    final api = customerApi;
    final phone = _pendingPhone;
    if (api == null || phone == null || _pendingRegistration == null) {
      emit(const AuthError('بيانات إنشاء الحساب غير متاحة. أعد إدخال بياناتك.'));
      return;
    }

    emit(AuthLoading());
    try {
      final request = await api.requestOtp(phone: phone, purpose: 'register');
      emit(AuthOtpRequired(phone: request.phone, otpRequestId: request.id));
    } catch (error) {
      emit(AuthError(_arabicAuthError(error)));
    }
  }

  Future<void> verifyRegistrationOtp({
    required int otpRequestId,
    required String code,
  }) async {
    final api = customerApi;
    final phone = _pendingPhone;
    final registration = _pendingRegistration;
    if (api == null || phone == null || registration == null) {
      emit(const AuthError('انتهت بيانات التسجيل. ارجع إلى التسجيل وأعد المحاولة.'));
      return;
    }
    if (code.trim().length != 6) {
      emit(const AuthError('أدخل رمز التحقق المكوّن من 6 أرقام.'));
      return;
    }

    emit(AuthLoading());
    try {
      final user = await api.verifyRegistrationOtp(
        otpRequestId: otpRequestId,
        code: code,
        phone: phone,
        registration: registration,
      );
      _pendingRegistration = null;
      _pendingPhone = null;
      emit(AuthAuthenticated(user));
    } catch (error) {
      emit(AuthError(_arabicAuthError(error)));
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    emit(AuthLoading());
    final result = await signInUsecase(SignInParams(
      email: email,
      password: password,
    ));
    result.fold(
      (error) {
        if (error.contains('تأكيد بريدك')) {
          emit(AuthEmailConfirmationRequired(email));
        } else {
          emit(AuthError(error));
        }
      },
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    emit(AuthLoading());
    final result = await signUpUsecase(SignUpParams(
      email: email,
      password: password,
      fullName: fullName,
      phone: phone,
    ));
    result.fold(
      (error) => emit(AuthError(error)),
      (user) => emit(AuthEmailConfirmationRequired(email)),
    );
  }

  Future<void> signOut() async {
    if (customerApi != null) {
      try {
        await customerApi!.logout();
        emit(AuthUnauthenticated());
        return;
      } catch (_) {
        // Fall back to the legacy sign-out path when a Flask session is absent.
      }
    }
    emit(AuthLoading());
    final result = await signOutUsecase(const NoParams());
    result.fold(
      (error) => emit(AuthError(error)),
      (_) => emit(AuthUnauthenticated()),
    );
  }

  Future<void> resetPassword(String email) async {
    emit(AuthLoading());
    final result = await resetPasswordUsecase(email);
    result.fold(
      (error) => emit(AuthError(error)),
      (_) => emit(AuthPasswordResetSent(email)),
    );
  }

  void clearError() {
    if (state is AuthError) emit(AuthUnauthenticated());
  }

  String _arabicAuthError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('invalid otp')) return 'رمز التحقق غير صحيح.';
    if (text.contains('otp has expired') || text.contains('expired')) {
      return 'انتهت صلاحية رمز التحقق. اطلب رمزًا جديدًا.';
    }
    if (text.contains('too many') || text.contains('rate limit')) {
      return 'تجاوزت عدد المحاولات المسموح. حاول لاحقًا.';
    }
    if (text.contains('phone or password') ||
        text.contains('phone or password') ||
        text.contains('رقم الهاتف أو كلمة المرور')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
    }
    if (text.contains('does not exist') || text.contains('not found')) {
      return 'لا توجد بيانات مطابقة. تحقق من الرقم ثم حاول مجددًا.';
    }
    if (text.contains('phone is required')) return 'أدخل رقم الهاتف.';
    if (text.contains('city')) return 'تعذر اعتماد المدينة المختارة.';
    if (text.contains('currency')) return 'تعذر اعتماد العملة المختارة.';
    if (text.contains('gender')) return 'اختر الجنس.';
    if (text.contains('password')) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
    if (text.contains('تعذر الاتصال بالخادم')) return error.toString();
    if (text.contains('flaskapiexception')) {
      final message = error.toString();
      final separator = message.indexOf(':');
      if (separator >= 0 && separator + 1 < message.length) {
        return message.substring(separator + 1).trim();
      }
    }
    return 'تعذر إتمام العملية الآن. تحقق من اتصالك وحاول مرة أخرى.';
  }
}
