import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_settings_service.dart';
import '../widgets/terms_and_conditions_dialog.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _keepMeLoggedIn = false;
  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _usernameController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter email/username and password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Load latest staff accounts & roles from Supabase
      await AppSettingsService.instance.reloadFromSupabase();

      final staffList = AppSettingsService.instance.staffAccounts;
      final matchedStaffIdx = staffList.indexWhere(
        (s) => s.email.toLowerCase() == email.toLowerCase(),
      );
      final StaffAccount? matchedStaff =
          matchedStaffIdx != -1 ? staffList[matchedStaffIdx] : null;

      if (matchedStaff != null && !matchedStaff.isActive) {
        await _supabase.auth.signOut();
        _showLoginErrorDialog(
          title: 'Account Deactivated',
          message: 'Access denied: Your staff account has been deactivated by the administrator.',
        );
        return;
      }

      // 2. If staff member has a configured account in Staff & Roles, authenticate and route automatically
      if (matchedStaff != null) {
        final actualRole = StaffAccount.normalizeRole(matchedStaff.role);

        if (actualRole == 'Admin') {
          // For Admin, attempt Supabase Auth first, with configured password fallback
          bool adminAuthOk = false;
          try {
            final res = await _supabase.auth.signInWithPassword(
              email: email,
              password: password,
            );
            if (res.user != null) adminAuthOk = true;
          } catch (_) {}

          if (!adminAuthOk) {
            final configuredPass = matchedStaff.password?.trim() ?? '';
            if (configuredPass.isNotEmpty && password == configuredPass) {
              adminAuthOk = true;
            }
          }

          if (!adminAuthOk) {
            _showLoginErrorDialog(
              title: 'Login Failed',
              message: 'Incorrect email or password. Please check your credentials and try again.',
            );
            return;
          }
        } else {
          // For Clerk and Inspector, authenticate with Supabase Auth first, then configured staff fallback
          bool passOk = false;
          try {
            final res = await _supabase.auth.signInWithPassword(
              email: email,
              password: password,
            );
            if (res.user != null) passOk = true;
          } catch (_) {}

          if (!passOk) {
            final configuredPass = matchedStaff.password?.trim() ?? '';
            if (configuredPass.isNotEmpty && password == configuredPass) {
              passOk = true;
            }
          }

          if (!passOk) {
            _showLoginErrorDialog(
              title: 'Login Failed',
              message: 'Incorrect email or password. Please check your credentials and try again.',
            );
            return;
          }
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('keepMeLoggedIn', _keepMeLoggedIn);

        if (actualRole == 'Admin') {
          await prefs.setString('admin_auth_email', email);
          await prefs.setString('admin_auth_password', password);
        }

        await AppSettingsService.instance.setActiveStaffSession(matchedStaff);
        // Ensure background Admin Supabase session is active so Clerk & Inspector pass RLS for all tables
        await AppSettingsService.instance.ensureAdminAuthSession();

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
        return;
      }

      // 3. Fallback: Standard Supabase Auth sign-in for users not yet in staff table
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user != null) {
        final metaRole = user.userMetadata?['role']?.toString() ?? '';
        if (metaRole != 'admin' &&
            metaRole != 'clerk' &&
            metaRole != 'inspector') {
          await _supabase.auth.signOut();
          _showLoginErrorDialog(
            title: 'Access Denied',
            message: 'Staff or Admin privileges required to access this portal.',
          );
          return;
        }

        final String actualRole = StaffAccount.normalizeRole(metaRole);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('keepMeLoggedIn', _keepMeLoggedIn);

        if (actualRole == 'Admin') {
          await prefs.setString('admin_auth_email', email);
          await prefs.setString('admin_auth_password', password);
          final existingAdminIdx = AppSettingsService.instance.staffAccounts.indexWhere(
            (s) => s.email.toLowerCase() == email.toLowerCase(),
          );
          if (existingAdminIdx != -1) {
            await AppSettingsService.instance.updateStaffPassword(
              AppSettingsService.instance.staffAccounts[existingAdminIdx].id,
              password,
            );
          } else {
            await AppSettingsService.instance.addStaffAccount(
              StaffAccount(
                id: user.id,
                fullName: user.userMetadata?['full_name']?.toString() ?? 'Slaughterhouse Administrator',
                email: email,
                role: 'Admin',
                isActive: true,
                createdAt: DateTime.now(),
                password: password,
              ),
            );
          }
        }

        await AppSettingsService.instance.setActiveStaffSession(null);
        AppSettingsService.instance.syncWithAuthUser(user);

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
        return;
      }
    } on AuthException catch (error) {
      final msg = error.message.toLowerCase();
      if (msg.contains('email not confirmed')) {
        _showLoginErrorDialog(
          title: 'Email Verification Required',
          message: 'Your email address has not been confirmed yet. Please check your email inbox and verify your email address before logging in.',
        );
      } else if (msg.contains('invalid login credentials') ||
          msg.contains('invalid') ||
          msg.contains('credential') ||
          msg.contains('password') ||
          msg.contains('user not found')) {
        _showLoginErrorDialog(
          title: 'Login Failed',
          message: 'Incorrect email or password. Please check your credentials and try again.',
        );
      } else {
        _showLoginErrorDialog(
          title: 'Login Failed',
          message: error.message,
        );
      }
    } catch (error) {
      _showLoginErrorDialog(
        title: 'Login Failed',
        message: 'Incorrect email or password or an unexpected error occurred. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showLoginErrorDialog({
    String title = 'Login Failed',
    String message = 'Incorrect email or password. Please check your credentials and try again.',
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Container(
            width: 400,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 42,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF475569),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showError(String message) {
    _showLoginErrorDialog(title: 'Login Notice', message: message);
  }

  void _showForgotPasswordDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Container(
            width: 440,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2FE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_person_outlined,
                    color: Color(0xFF0284C7),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Password Reset & Recovery',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'For municipal regulatory compliance and security, administrative accounts do not allow public self-service password resets.\n\nPlease contact the City Veterinary Office IT Administrator or the System Database Administrator to request an authorized credential reset.\n\nOnce logged in, administrators can securely update their personal password at any time in Settings → My Profile.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF475569),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Understood',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset('assets/images/BG.jpeg', fit: BoxFit.cover),
          ),
          // Dark Overlay
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(),
          ),
          // Main Content
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 1.0, sigmaY: 1.0),
                    child: Container(
                      width: 1000,
                      height: 600,
                      decoration: BoxDecoration(
                        color: const Color(0xCC1E2828).withValues(alpha: 0.75), 
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Stack(
                        children: [
                          // Back button
                          Positioned(
                            top: 20,
                            left: 20,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white70),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          Row(
                            children: [
                              // Left Side - Welcome text
                              Expanded(
                                flex: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(60.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Welcome Tabaco City Slaughterhouse',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 32,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                      const SizedBox(height: 30),
                                      Text(
                                        'To the official Slaughterhouse Management Portal. This secure platform allows staff and authorized personnel to manage and monitor slaughter operations efficiently.',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          fontSize: 16,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Divider
                              Container(
                                width: 1,
                                height: 400,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              // Right Side - Form
                              Expanded(
                                flex: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(60.0),
                                  child: _buildLoginForm(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome',
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 6),
            const Text(
              'City Slaughterhouse Management Portal',
              style: TextStyle(color: Colors.white70, fontSize: 14.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _usernameController,
              label: 'Email / Username',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              isPassword: true,
              obscureText: _obscurePassword,
              onToggleObscure: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _keepMeLoggedIn,
                        onChanged: (value) {
                          setState(() => _keepMeLoggedIn = value ?? false);
                        },
                        fillColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return const Color(0xFF2D6A4F);
                          }
                          return Colors.transparent;
                        }),
                        side: const BorderSide(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Keep me logged in', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
                TextButton(
                  onPressed: _showForgotPasswordDialog,
                  child: const Text('Forgot password?', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Sign In', style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Authorized personnel only. Access is automatically governed by your assigned staff role.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 11.5),
            ),
            const SizedBox(height: 18),
            Center(
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const TermsAndConditionsDialog(),
                  );
                },
                child: const Text(
                  'Terms & Conditions and User Agreement',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 45,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.9), 
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide.none,
              ),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        obscureText ? Icons.visibility_off : Icons.visibility,
                        color: const Color(0xFF2D6A4F),
                        size: 20,
                      ),
                      onPressed: onToggleObscure,
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: ClipOval(
                child: Image.asset('assets/images/logo1.png', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Tabaco City Slaughterhouse',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}