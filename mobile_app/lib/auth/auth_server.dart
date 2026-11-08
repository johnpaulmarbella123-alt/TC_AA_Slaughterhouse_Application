import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {

  final SupabaseClient _supabase =
      Supabase.instance.client;

  // =========================
  // SIGN IN
  // =========================
  Future<AuthResponse> signIn(
    String emailOrPhone,
    String password,
  ) async {

    if (emailOrPhone.contains('@')) {

      return await _supabase.auth.signInWithPassword(
        email: emailOrPhone,
        password: password,
      );

    } else {

      // Convert local format (09...) to international format (+63...)
      String phone = emailOrPhone;
      if (phone.startsWith('09')) {
        phone = '+63${phone.substring(1)}';
      }

      return await _supabase.auth.signInWithPassword(
        phone: phone,
        password: password,
      );
    }
  }

  // =========================
// SIGN UP
// =========================
Future<AuthResponse> signUp(
  String emailOrPhone,
  String password,
  String displayName,
  String address,
) async {

  AuthResponse response;

  // EMAIL SIGNUP
  if (emailOrPhone.contains('@')) {

    response = await _supabase.auth.signUp(
      email: emailOrPhone,
      password: password,

      data: {
        'display_name': displayName,
        'address': address,
      },
    );

  } else {

    // PHONE SIGNUP
    response = await _supabase.auth.signUp(
      phone: emailOrPhone,
      password: password,

      data: {
        'display_name': displayName,
        'address': address,
      },
    );
  }

  // SAVE USER TO profiles TABLE
  final user = response.user;

  if (user != null) {

      final isEmail = emailOrPhone.contains('@');
      final emailValue = isEmail ? emailOrPhone : (user.email ?? '');
      final phoneValue = isEmail ? (user.phone ?? '') : emailOrPhone;

      await _supabase
          .from('profiles')
          .upsert({
        'id': user.id,
        'display_name': displayName,
        'email': emailValue.isNotEmpty ? emailValue : null,
        'phone': phoneValue,
        'address': address,
      });
    }

  return response;
}
  // =========================
  // SEND OTP (EMAIL OR PHONE)
  // =========================
  Future<void> sendOtp(String emailOrPhone) async {
    if (emailOrPhone.contains('@')) {
      await _supabase.auth.signInWithOtp(
        email: emailOrPhone.trim(),
      );
    } else {
      String phone = emailOrPhone.trim();
      if (phone.startsWith('09')) {
        phone = '+63${phone.substring(1)}';
      }
      await _supabase.auth.signInWithOtp(
        phone: phone,
      );
    }
  }

  // =========================
  // SIGN OUT
  // =========================
  Future<void> signOut() async {

    await _supabase.auth.signOut();
  }

  // =========================
  // RESET PASSWORD - SEND OTP (EMAIL OR PHONE)
  // =========================
  Future<void> sendPasswordResetOtp(String emailOrPhone) async {
    final identifier = emailOrPhone.trim();
    if (identifier.contains('@')) {
      await _supabase.auth.resetPasswordForEmail(identifier);
    } else {
      String phone = identifier;
      if (phone.startsWith('09')) {
        phone = '+63${phone.substring(1)}';
      }
      await _supabase.auth.signInWithOtp(phone: phone);
    }
  }

  // =========================
  // RESET PASSWORD - VERIFY & UPDATE (EMAIL OR PHONE)
  // =========================
  Future<void> resetPasswordWithOtp({
    required String emailOrPhone,
    required String token,
    required String newPassword,
  }) async {
    final identifier = emailOrPhone.trim();
    if (identifier.contains('@')) {
      // 1. Verify recovery OTP token for email
      await _supabase.auth.verifyOTP(
        email: identifier,
        token: token.trim(),
        type: OtpType.recovery,
      );
    } else {
      String phone = identifier;
      if (phone.startsWith('09')) {
        phone = '+63${phone.substring(1)}';
      }
      // 1. Verify SMS OTP token for phone
      await _supabase.auth.verifyOTP(
        phone: phone,
        token: token.trim(),
        type: OtpType.sms,
      );
    }

    // 2. Update user's password
    await _supabase.auth.updateUser(
      UserAttributes(password: newPassword.trim()),
    );

    // 3. Sign out of the temporary session so user can log in with new password
    await _supabase.auth.signOut();
  }

  // =========================
  // FIND EMAIL FOR PHONE (FALLBACK)
  // =========================
  Future<String?> findEmailForPhone(String phoneInput) async {
    try {
      String clean = phoneInput.trim().replaceAll(RegExp(r'\s+|-'), '');
      String intl = clean.startsWith('09')
          ? '+63${clean.substring(1)}'
          : (clean.startsWith('+63') ? clean : '+63$clean');
      String local = clean.startsWith('+63')
          ? '0${clean.substring(3)}'
          : (clean.startsWith('09') ? clean : '0$clean');

      final data = await _supabase
          .from('profiles')
          .select('email')
          .or('phone.eq.$intl,phone.eq.$local,phone.eq.$clean')
          .not('email', 'is', null)
          .limit(1)
          .maybeSingle();

      return data?['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  // =========================
  // GET USER EMAIL
  // =========================
  String? getUserEmail() {

    final session =
        _supabase.auth.currentSession;

    final user = session?.user;

    return user?.email;
  }
}