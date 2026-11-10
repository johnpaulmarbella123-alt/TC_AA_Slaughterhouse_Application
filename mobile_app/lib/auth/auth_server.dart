import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {

  final SupabaseClient _supabase =
      Supabase.instance.client;

  // =========================
  // PHONE FORMATTING HELPER
  // =========================
  String formatToE164Phone(String raw) {
    String clean = raw.trim().replaceAll(RegExp(r'\s+|-'), '');
    if (clean.startsWith('09')) {
      return '+63${clean.substring(1)}';
    }
    if (clean.startsWith('9') && clean.length == 10) {
      return '+63$clean';
    }
    if (clean.startsWith('+63')) {
      return clean;
    }
    if (clean.startsWith('63') && clean.length == 12) {
      return '+$clean';
    }
    return clean;
  }

  // =========================
  // CHECK IF ACCOUNT EXISTS
  // =========================
  Future<bool> isAccountExists(String identifier) async {
    final clean = identifier.trim();
    if (clean.isEmpty) return false;

    // 1. Check via check_account_status RPC
    try {
      final res = await _supabase.rpc(
        'check_account_status',
        params: {'identifier': clean},
      );
      if (res != null) {
        final Map data = res is Map ? res : jsonDecode(res.toString());
        if (data['exists'] == true) {
          return true;
        }
      }
    } catch (_) {}

    // 2. Direct profiles table check
    try {
      if (clean.contains('@')) {
        final profile = await _supabase
            .from('profiles')
            .select('id')
            .ilike('email', clean.toLowerCase())
            .limit(1)
            .maybeSingle();
        if (profile != null) return true;
      } else {
        final formattedPhone = formatToE164Phone(clean);
        String local = formattedPhone.startsWith('+63')
            ? '0${formattedPhone.substring(3)}'
            : formattedPhone;

        final profile = await _supabase
            .from('profiles')
            .select('id')
            .or('phone.eq.$formattedPhone,phone.eq.$local,phone.eq.$clean')
            .limit(1)
            .maybeSingle();
        if (profile != null) return true;

        if (formattedPhone != clean) {
          try {
            final resPhone = await _supabase.rpc(
              'check_account_status',
              params: {'identifier': formattedPhone},
            );
            if (resPhone != null) {
              final Map data = resPhone is Map ? resPhone : jsonDecode(resPhone.toString());
              if (data['exists'] == true) {
                return true;
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return false;
  }

  // =========================
  // SIGN IN
  // =========================
  Future<AuthResponse> signIn(
    String emailOrPhone,
    String password,
  ) async {
    final clean = emailOrPhone.trim();

    if (clean.contains('@')) {
      return await _supabase.auth.signInWithPassword(
        email: clean.toLowerCase(),
        password: password,
      );
    } else {
      // It's a phone number
      // 1. Dual-identifier login: resolve linked account email from profiles
      final linkedEmail = await findEmailForPhone(clean);
      if (linkedEmail != null && linkedEmail.isNotEmpty) {
        try {
          return await _supabase.auth.signInWithPassword(
            email: linkedEmail.toLowerCase(),
            password: password,
          );
        } catch (e) {
          // If signing in with linked email failed, fallback to direct phone sign-in
          final formattedPhone = formatToE164Phone(clean);
          try {
            return await _supabase.auth.signInWithPassword(
              phone: formattedPhone,
              password: password,
            );
          } catch (_) {
            rethrow;
          }
        }
      }

      // 2. Direct phone login (for phone-only registered users)
      final formattedPhone = formatToE164Phone(clean);
      return await _supabase.auth.signInWithPassword(
        phone: formattedPhone,
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
        email: emailOrPhone.trim().toLowerCase(),
      );
    } else {
      final phone = formatToE164Phone(emailOrPhone);
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
      await _supabase.auth.resetPasswordForEmail(identifier.toLowerCase());
    } else {
      final phone = formatToE164Phone(identifier);
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
        email: identifier.toLowerCase(),
        token: token.trim(),
        type: OtpType.recovery,
      );
    } else {
      final phone = formatToE164Phone(identifier);
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
  // FIND EMAIL FOR PHONE (FALLBACK / DUAL IDENTIFIER)
  // =========================
  Future<String?> findEmailForPhone(String phoneInput) async {
    try {
      final clean = phoneInput.trim().replaceAll(RegExp(r'\s+|-'), '');
      final intl = formatToE164Phone(clean);
      final local = intl.startsWith('+63')
          ? '0${intl.substring(3)}'
          : clean;

      final data = await _supabase
          .from('profiles')
          .select('email')
          .or('phone.eq.$intl,phone.eq.$local,phone.eq.$clean')
          .not('email', 'is', null)
          .limit(1)
          .maybeSingle();

      final email = data?['email'] as String?;
      if (email != null && email.trim().isNotEmpty) {
        return email.trim();
      }
      return null;
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