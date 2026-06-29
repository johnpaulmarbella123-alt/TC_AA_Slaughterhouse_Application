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

      return await _supabase.auth.signInWithPassword(
        phone: emailOrPhone,
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

    await _supabase
        .from('profiles')
        .upsert({

      'id': user.id,

      'display_name': displayName,

      'phone': emailOrPhone.contains('@')
          ? ''
          : emailOrPhone,

      'address': address,
    });
  }

  return response;
}
  // =========================
  // SEND OTP
  // =========================
  Future<void> sendOtp(String phone) async {

    await _supabase.auth.signInWithOtp(
      phone: phone,
    );
  }

  // =========================
  // SIGN OUT
  // =========================
  Future<void> signOut() async {

    await _supabase.auth.signOut();
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