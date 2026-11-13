import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_server.dart';
import '../screen/how_it_works.dart';
import '../widgets/terms_and_conditions_dialog.dart';
import 'forgot_password_page.dart';
import 'home_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    final rawInput = _emailController.text.trim();
    final password = _passwordController.text.trim();
    try {
      // ignore: avoid_print
      print('Attempting login for: $rawInput');
      final response = await _authService.signIn(
        rawInput,
        password,
      );
      // ignore: avoid_print
      print('Login response received: ${response.user?.id}');
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_previously_logged_in', true);
      } catch (_) {}

      if (mounted) {
        // ignore: avoid_print
        print('Navigating to /HOME');
        globalAvatarUrl.value = null;
        Navigator.pushNamedAndRemoveUntil(context, '/HOME', (route) => false);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Login error: $e');
      if (mounted) {
        final msg = e.toString();
        final lower = msg.toLowerCase();
        if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No internet connection. Please check your Wi-Fi or mobile data.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (lower.contains('account deactivated')) {
          _showFacebookStyleLoginErrorDialog(
            customTitle: 'Account Deactivated',
            customMessage: msg,
          );
        } else if (lower.contains('has been deleted')) {
          _showFacebookStyleLoginErrorDialog(
            isPasswordError: false,
            isUnverified: false,
          );
        } else if (e is AuthException &&
            !e.message.toLowerCase().contains('invalid login credentials') &&
            !e.message.toLowerCase().contains('invalid_credentials') &&
            !e.message.toLowerCase().contains('email not confirmed') &&
            !e.message.toLowerCase().contains('phone not confirmed')) {
          _showFacebookStyleLoginErrorDialog(
            customTitle: 'Login Failed',
            customMessage: e.message,
          );
        } else {
          // Check live status of the account via RPC to determine exact error
          bool isPasswordError = false;
          bool isUnverified = false;

          try {
            String checkIdentifier = rawInput;
            if (!checkIdentifier.contains('@')) {
              final linkedEmail = await _authService.findEmailForPhone(checkIdentifier);
              if (linkedEmail != null && linkedEmail.isNotEmpty) {
                checkIdentifier = linkedEmail;
              } else {
                checkIdentifier = _authService.formatToE164Phone(checkIdentifier);
              }
            }

            final res = await Supabase.instance.client.rpc(
              'check_account_status',
              params: {'identifier': checkIdentifier},
            );
            if (res != null) {
              final Map data = res is Map ? res : jsonDecode(res.toString());
              final bool exists = data['exists'] == true;
              final bool isVerified = data['is_verified'] == true;
              if (exists && isVerified) {
                isPasswordError = true;
              } else if (exists && !isVerified) {
                isUnverified = true;
              } else {
                isPasswordError = false;
                isUnverified = false;
              }
            } else {
              final exists = await _authService.isAccountExists(rawInput);
              if (exists) {
                isPasswordError = true;
              }
            }
          } catch (_) {
            // Fallback: check database directly
            final exists = await _authService.isAccountExists(rawInput);
            if (exists) {
              if (lower.contains('email not confirmed') ||
                  lower.contains('not confirmed') ||
                  lower.contains('unverified')) {
                isUnverified = true;
              } else {
                isPasswordError = true;
              }
            } else {
              isPasswordError = false;
              isUnverified = false;
            }
          }

          if (mounted) {
            if (isUnverified) {
              _showFacebookStyleLoginErrorDialog(isUnverified: true);
            } else if (isPasswordError) {
              _showFacebookStyleLoginErrorDialog(isPasswordError: true);
            } else {
              _showFacebookStyleLoginErrorDialog(isPasswordError: false, isUnverified: false);
            }
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFacebookStyleLoginErrorDialog({
    bool isPasswordError = true,
    bool isUnverified = false,
    String? customTitle,
    String? customMessage,
  }) {
    final title = customTitle ??
        (isUnverified
            ? 'Account Not Verified'
            : (isPasswordError ? 'Incorrect password' : 'Account not found'));
    final message = customMessage ??
        (isUnverified
            ? "Your account has not been verified yet. Please sign up or complete verification to proceed."
            : (isPasswordError
                ? "We can help you log in to your account if you've forgotten your password."
                : "We couldn't find an account matching that email or mobile number. Would you like to create one?"));
    final primaryActionText = isUnverified
        ? 'Sign Up'
        : (isPasswordError ? 'Forgotten password' : 'Create an account');

    const brandGreen = Color(0xFF218358);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
              InkWell(
                onTap: () async {
                  Navigator.pop(ctx);
                  if (isUnverified) {
                    Navigator.pushNamed(context, '/SIGNUP');
                  } else if (isPasswordError) {
                    final identifierFromReset = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ForgotPasswordScreen(
                          initialIdentifier: _emailController.text.trim().isNotEmpty
                              ? _emailController.text.trim()
                              : null,
                        ),
                      ),
                    );
                    if (identifierFromReset != null && identifierFromReset.isNotEmpty) {
                      _emailController.text = identifierFromReset;
                    }
                    _passwordController.clear();
                  } else {
                    Navigator.pushNamed(context, '/SIGNUP');
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  child: Text(
                    primaryActionText,
                    style: const TextStyle(
                      fontSize: 16,
                      color: brandGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
              InkWell(
                onTap: () => Navigator.pop(ctx),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  child: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontSize: 16,
                      color: brandGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background Ornaments
          Positioned(
            top: -size.width * 0.3,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,
              decoration: const BoxDecoration(
                color: Color(0xFFE0E0E0),
                shape: BoxShape.circle,
              ),
              alignment: const Alignment(-1.3, 0.5),
              child: const Padding(
                padding: EdgeInsets.all(40.0),
                child: Text(
                  "Hi Welcome!\nGreate to see you again!!",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size.width * 0.5,
            left: -size.width * 0.2,
            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,
              decoration: const BoxDecoration(
                color: Color(0xFFE0E0E0),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    // Back Button
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.arrow_back_ios, size: 18),
                          SizedBox(width: 4),
                          Text(
                            "Log in",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100),
                    // Title
                    const Center(
                      child: Text(
                        "Log In",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationThickness: 2,
                      ),
  ),
),
                    const SizedBox(height: 40),
                    // Form Fields
                    _buildInputField(
                      hint: "Enter email or phone Number",
                      icon: Icons.mail_outline,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      hint: "Enter password",
                      icon: Icons.lock_outline,
                      isPassword: true,
                      obscureText: _obscurePassword,
                      controller: _passwordController,
                      onToggleVisibility: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    // Forget Password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final identifierFromReset = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ForgotPasswordScreen(
                                initialIdentifier: _emailController.text.trim().isNotEmpty
                                    ? _emailController.text.trim()
                                    : null,
                              ),
                            ),
                          );
                          if (identifierFromReset != null && identifierFromReset.isNotEmpty) {
                            _emailController.text = identifierFromReset;
                            _passwordController.clear();
                          }
                        },
                        child: const Text(
                          "Forget password?",
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Main Action
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF218358),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Log In",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Footer Link
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/SIGNUP');
                        },
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(color: Colors.black54, fontSize: 14),
                            children: [
                              TextSpan(text: "Don’t have an account? "),
                              TextSpan(
                                text: "Register here!",
                                style: TextStyle(
                                  color: Color(0xFF218358),
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // How It Works Text Link
                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HowItWorksScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minimumSize: const Size(100, 44),
                        ),
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(color: Colors.black54, fontSize: 14),
                            children: [
                              TextSpan(text: "How it works? "),
                              TextSpan(
                                text: "Click here",
                                style: TextStyle(
                                  color: Color(0xFF218358),
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Terms & Conditions Link
                    Center(
                      child: TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => const TermsAndConditionsDialog(),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: const Size(100, 32),
                        ),
                        child: const Text(
                          "Terms & Conditions and User Agreement",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    TextEditingController? controller,
    VoidCallback? onToggleVisibility,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autocorrect = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE9E9E9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        autocorrect: autocorrect,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.grey, size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: onToggleVisibility,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
