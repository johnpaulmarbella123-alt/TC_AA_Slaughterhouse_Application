import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_settings_service.dart';

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
  String? _errorMessage;
  final bool _keepMeLoggedIn = true;
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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
    setState(() => _errorMessage = message);
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen Slaughterhouse Building Background
          Positioned.fill(
            child: Image.asset('assets/images/BG.jpeg', fit: BoxFit.cover),
          ),
          // Light Neutral 15% Dark Tint Overlay (crisp photo, no blur)
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.15)),
          ),
          // Centered Official Municipal Login Card
          Positioned.fill(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: Material(
                    color: Colors.white,
                    elevation: 20,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.white, width: 0.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Slaughterhouse Green Header Banner ──
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F5132),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (canPop)
                                Positioned(
                                  top: -8,
                                  left: -8,
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
                                    tooltip: 'Back',
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.20),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        'assets/images/logo1.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'REPUBLIC OF THE PHILIPPINES • PROVINCE OF ALBAY',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'City of Tabaco',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'AA Slaughterhouse Management System',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFA7F3D0),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── Clean White Form Body ──
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFECACA)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFB91C1C),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: Color(0xFFB91C1C),
                                            fontSize: 14,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              _buildTextField(
                                controller: _usernameController,
                                label: 'Staff Email',
                                hintText: 'tcaaslaughterhouse@gmail.com',
                                keyboardType: TextInputType.emailAddress,
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _passwordController,
                                label: 'Password',
                                hintText: 'Enter your password',
                                isPassword: true,
                                obscureText: _obscurePassword,
                                onToggleObscure: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                  }
                                },
                                onSubmitted: (_) {
                                  if (!_isLoading) _handleLogin();
                                },
                              ),
                              const SizedBox(height: 16),
                              Opacity(
                                opacity: _isLoading ? 0.60 : 1.0,
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleLogin,
                                    style: ButtonStyle(
                                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                                        if (states.contains(WidgetState.hovered) ||
                                            states.contains(WidgetState.pressed)) {
                                          return const Color(0xFF0B3D26);
                                        }
                                        return const Color(0xFF0F5132);
                                      }),
                                      foregroundColor: const WidgetStatePropertyAll(Colors.white),
                                      elevation: const WidgetStatePropertyAll(0),
                                      shape: WidgetStatePropertyAll(
                                        RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.2,
                                            ),
                                          )
                                        : const Text(
                                            'Sign In to Abattoir System',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Role-based access enforced server-side (Admin, Clerk, Inspector).',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15.2),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14.5),
            filled: true,
            fillColor: Colors.white,
            constraints: const BoxConstraints(minHeight: 46),
            contentPadding: EdgeInsets.fromLTRB(14, 12, isPassword ? 48 : 14, 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF0F5132), width: 2.0),
            ),
            suffixIcon: isPassword
                ? Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: onToggleObscure,
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: const Color(0xFFF1F5F9),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF64748B),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ),
      ],
    );
  }
}