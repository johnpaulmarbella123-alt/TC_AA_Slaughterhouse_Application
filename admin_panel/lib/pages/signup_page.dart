import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_settings_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isChecking = true;
  bool _isAdminAlreadyProvisioned = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool provisioned = false;

      // 1. Strict live check: check profiles for an existing active admin user
      try {
        final res = await _supabase
            .from('profiles')
            .select('id, role')
            .eq('role', 'admin')
            .limit(1);
        if ((res as List).isNotEmpty) {
          provisioned = true;
        } else {
          // If no admin profile exists in Supabase, auto-clean stale settings & local cache
          try {
            await _supabase
                .from('system_settings')
                .delete()
                .eq('key', 'admin_account_provisioned');
          } catch (_) {}
          await prefs.remove('admin_account_provisioned');
        }
      } catch (_) {}

      // Sync local preferences with true database reality
      await prefs.setBool('admin_account_provisioned', provisioned);

      if (mounted) {
        setState(() {
          _isAdminAlreadyProvisioned = provisioned;
          _isChecking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    final email = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      _showError('Please enter a valid, verified email address.');
      return;
    }

    if (password != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters long');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final defaultFullName = email.split('@').first.toUpperCase();

      // Sign up administrator in Supabase Auth
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'role': 'admin',
          'full_name': defaultFullName,
        },
      );

      if (mounted && response.user != null) {
        final user = response.user!;

        // 1. Ensure profile in public.profiles table has role 'admin'
        try {
          await _supabase.from('profiles').upsert({
            'id': user.id,
            'full_name': defaultFullName,
            'role': 'admin',
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}

        // 2. Mark admin as permanently provisioned in DB and local prefs
        await prefs.setBool('admin_account_provisioned', true);
        await prefs.setString('admin_auth_email', email);
        await prefs.setString('admin_auth_password', password);

        try {
          await _supabase.from('system_settings').upsert({
            'key': 'admin_account_provisioned',
            'value': {
              'id': user.id,
              'email': email,
              'role': 'admin',
              'created_at': DateTime.now().toIso8601String(),
            },
          });
        } catch (_) {}

        // 3. Sync with AppSettingsService and add to Staff Accounts list
        AppSettingsService.instance.staffAccounts.removeWhere(
          (s) => s.email.toLowerCase() == 'admin@tabaco.gov.ph',
        );

        final existsInStaff = AppSettingsService.instance.staffAccounts
            .any((s) => s.email.toLowerCase() == email.toLowerCase());
        if (!existsInStaff) {
          await AppSettingsService.instance.addStaffAccount(
            StaffAccount(
              id: user.id,
              fullName: defaultFullName,
              email: email,
              role: 'Admin',
              isActive: true,
              createdAt: DateTime.now(),
              password: password,
            ),
          );
        }

        AppSettingsService.instance.syncWithAuthUser(user);

        // Instant Demo Activation: Grant immediate dashboard entry for defense
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Demo Administrator account ($email) registered and activated in Supabase!'),
              backgroundColor: const Color(0xFF2D6A4F),
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
      }
    } on AuthException catch (error) {
      final msg = error.message.toLowerCase();
      // If account already exists in Supabase Auth, sign in to link & activate
      if (msg.contains('already registered') || msg.contains('already exists')) {
        try {
          final loginRes = await _supabase.auth.signInWithPassword(email: email, password: password);
          if (loginRes.user != null) {
            final user = loginRes.user!;
            final defaultFullName = email.split('@').first.toUpperCase();
            final prefs = await SharedPreferences.getInstance();

            try {
              await _supabase.from('profiles').upsert({
                'id': user.id,
                'full_name': defaultFullName,
                'role': 'admin',
                'updated_at': DateTime.now().toIso8601String(),
              });
              await _supabase.from('system_settings').upsert({
                'key': 'admin_account_provisioned',
                'value': {
                  'id': user.id,
                  'email': email,
                  'role': 'admin',
                  'created_at': DateTime.now().toIso8601String(),
                },
              });
            } catch (_) {}

            await prefs.setBool('admin_account_provisioned', true);
            await prefs.setString('admin_auth_email', email);
            await prefs.setString('admin_auth_password', password);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Administrator account verified and activated! Welcome aboard.'),
                  backgroundColor: Color(0xFF2D6A4F),
                ),
              );
              Navigator.pushReplacementNamed(context, '/dashboard');
              return;
            }
          }
        } catch (_) {}
      }
      _showError(error.message);
    } catch (error) {
      _showError('An unexpected error occurred during registration.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
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
                                  child: _buildSignupForm(),
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

  Widget _buildSignupForm() {
    if (_isChecking) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }

    if (_isAdminAlreadyProvisioned) {
      return Center(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline, color: Colors.amber, size: 32),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Registration Closed',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The official Administrator account has already been registered for Tabaco City Slaughterhouse.\n\nAll staff accounts (Clerk and Inspector) are provisioned directly by the Administrator inside Settings → Staff & Roles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Return to Staff Login', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    setState(() => _isChecking = true);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('admin_account_provisioned');
                    await _checkAdminStatus();
                  },
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  label: const Text('Re-check / Register New Admin', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Administrator Setup',
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Register primary admin account',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _usernameController,
              label: 'Verified Admin Email',
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
            const SizedBox(height: 16),
            _buildTextField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              isPassword: true,
              obscureText: _obscureConfirmPassword,
              onToggleObscure: () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 220,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Register Admin', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account? ', style: TextStyle(color: Colors.white70)),
                GestureDetector(
                  onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                  child: const Text(
                    'log in',
                    style: TextStyle(color: Colors.white, decoration: TextDecoration.underline),
                  ),
                ),
              ],
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
        const SizedBox(height: 6),
        SizedBox(
          height: 35,
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