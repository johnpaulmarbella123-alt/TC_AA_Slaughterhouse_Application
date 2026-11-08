import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_server.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialIdentifier;

  const ForgotPasswordScreen({super.key, this.initialIdentifier});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();

  // Controllers
  late final TextEditingController _identifierController;
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // State
  int _currentStep = 0; // 0 = Request Code, 1 = Verify & Reset
  bool _isLoading = false;
  bool _isResending = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  // Active identifier being recovered
  String _activeIdentifier = '';
  String? _enteredPhone;
  bool get _isEmail => _activeIdentifier.contains('@');

  // Resend Timer
  Timer? _resendTimer;
  int _resendCountdown = 60;

  @override
  void initState() {
    super.initState();
    _identifierController =
        TextEditingController(text: widget.initialIdentifier ?? '');
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      }
    });
  }

  String _formatPhone(String raw) {
    String phone = raw.trim().replaceAll(RegExp(r'\s+|-'), '');
    if (phone.startsWith('09')) {
      return '+63${phone.substring(1)}';
    }
    if (phone.startsWith('9') && phone.length == 10) {
      return '+63$phone';
    }
    return phone;
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '$name***@$domain';
    return '${name.substring(0, 2)}***@$domain';
  }

  // ═══════════════════════════════════════════════════
  //  STEP 1: SEND RECOVERY CODE (EMAIL OR PHONE)
  // ═══════════════════════════════════════════════════
  Future<void> _sendRecoveryCode({String? overrideIdentifier}) async {
    final rawInput = (overrideIdentifier ?? _identifierController.text).trim();

    if (rawInput.isEmpty) {
      _showSnackbar('Please enter your email or phone number.', isError: true);
      return;
    }

    final isEmailInput = rawInput.contains('@');

    if (isEmailInput) {
      final emailRegex = RegExp(r'^[\w\.\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$');
      if (!emailRegex.hasMatch(rawInput)) {
        _showSnackbar('Please enter a valid email address.', isError: true);
        return;
      }

      setState(() {
        _isLoading = true;
        _activeIdentifier = rawInput;
        _enteredPhone = null;
      });

      try {
        await _authService.sendPasswordResetOtp(rawInput);
        if (!mounted) return;

        _startResendTimer();
        setState(() => _currentStep = 1);

        _showSnackbar(
          'Recovery code sent! Please check your email inbox.',
          isError: false,
        );
      } catch (e) {
        if (!mounted) return;
        String msg = e.toString();
        if (e is AuthException) {
          msg = e.message;
        }
        if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
          msg = 'No internet connection. Please check your network.';
        } else if (msg.contains('rate limit')) {
          msg = 'Too many requests. Please wait a moment before trying again.';
        }
        _showSnackbar(msg, isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      // Validate phone number format
      final formattedPhone = _formatPhone(rawInput);
      if (!formattedPhone.startsWith('+639') || formattedPhone.length != 13) {
        _showSnackbar(
          'Please enter a valid 11-digit mobile number (e.g., 09123456789).',
          isError: true,
        );
        return;
      }

      setState(() => _isLoading = true);

      try {
        // Look up registered email linked to this phone number
        final linkedEmail = await _authService.findEmailForPhone(formattedPhone);

        if (linkedEmail == null || linkedEmail.isEmpty) {
          if (!mounted) return;
          _showSnackbar(
            'No registered account found with mobile number $rawInput. Please enter your email address.',
            isError: true,
          );
          return;
        }

        // Send 6-digit recovery OTP directly to their linked email
        await _authService.sendPasswordResetOtp(linkedEmail);
        if (!mounted) return;

        _startResendTimer();
        setState(() {
          _activeIdentifier = linkedEmail;
          _enteredPhone = rawInput;
          _currentStep = 1;
        });

        _showSnackbar(
          'Account found! 6-digit code sent to your linked email (${_maskEmail(linkedEmail)}).',
          isError: false,
        );
      } catch (e) {
        if (!mounted) return;
        _showSnackbar('Error sending code: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════
  //  RESEND CODE
  // ═══════════════════════════════════════════════════
  Future<void> _resendRecoveryCode() async {
    if (_resendCountdown > 0 || _isResending) return;

    setState(() => _isResending = true);

    try {
      await _authService.sendPasswordResetOtp(_activeIdentifier);
      if (!mounted) return;

      _startResendTimer();
      _showSnackbar(
        _enteredPhone != null
            ? 'A new recovery code has been sent to ${_maskEmail(_activeIdentifier)}.'
            : 'A new recovery code has been sent to your email.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Failed to resend code: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  // ═══════════════════════════════════════════════════
  //  STEP 2: VERIFY OTP & RESET PASSWORD
  // ═══════════════════════════════════════════════════
  Future<void> _resetPassword() async {
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (otp.isEmpty || otp.length < 6) {
      _showSnackbar('Please enter the complete 6-digit verification code.', isError: true);
      return;
    }

    if (newPassword.length < 6) {
      _showSnackbar('Password must be at least 6 characters long.', isError: true);
      return;
    }

    if (newPassword != confirmPassword) {
      _showSnackbar('Passwords do not match. Please try again.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.resetPasswordWithOtp(
        emailOrPhone: _activeIdentifier,
        token: otp,
        newPassword: newPassword,
      );

      if (!mounted) return;
      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (e is AuthException) {
        msg = e.message;
      }
      if (msg.contains('Token has expired') ||
          msg.contains('invalid') ||
          msg.contains('expired')) {
        msg = 'Invalid or expired verification code. Please check or request a new one.';
      } else if (msg.contains('SocketException')) {
        msg = 'No internet connection. Please check your network.';
      }
      _showSnackbar(msg, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ═══════════════════════════════════════════════════
  //  SUCCESS DIALOG
  // ═══════════════════════════════════════════════════
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF218358),
                size: 38,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Password Reset Successful!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your password has been updated. You can now log in using your new credentials.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context, _enteredPhone ?? _activeIdentifier); // Return to login with identifier
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF218358),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Back to Log In',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF218358),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
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
          // Background Ornaments (matching Login Screen)
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

          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // Top Back Navigation
                  InkWell(
                    onTap: () {
                      if (_currentStep == 1) {
                        setState(() => _currentStep = 0);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back_ios, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          _currentStep == 1 ? 'Change Account' : 'Back to Login',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Header Icon
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF218358).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _currentStep == 0
                            ? Icons.lock_reset_rounded
                            : (_isEmail
                                ? Icons.mark_email_read_outlined
                                : Icons.sms_outlined),
                        size: 38,
                        color: const Color(0xFF218358),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Header Title
                  Center(
                    child: Text(
                      _currentStep == 0 ? 'Forgot Password' : 'Reset Password',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Header Subtitle
                  Center(
                    child: Text(
                      _currentStep == 0
                          ? 'Enter your registered email address or mobile number to receive a 6-digit recovery code.'
                          : 'Enter the 6-digit verification code sent to your ${_isEmail ? 'email' : 'phone'} and your new password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ),

                  if (_currentStep == 1) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF218358).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_enteredPhone != null) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.phone_android, size: 13, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Mobile: $_enteredPhone',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.email_outlined, size: 14, color: Color(0xFF218358)),
                                const SizedBox(width: 6),
                                Text(
                                  _enteredPhone != null
                                      ? 'Code sent to: ${_maskEmail(_activeIdentifier)}'
                                      : _activeIdentifier,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF218358),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // ─── STEP 0: IDENTIFIER FORM (EMAIL OR PHONE) ───
                  if (_currentStep == 0) ...[
                    _buildInputField(
                      hint: 'Enter email or phone number',
                      icon: Icons.account_circle_outlined,
                      controller: _identifierController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _sendRecoveryCode(),
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
                                'Send Verification Code',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(color: Colors.black54, fontSize: 14),
                            children: [
                              TextSpan(text: 'Remember your password? '),
                              TextSpan(
                                text: 'Log In',
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
                  ],

                  // ─── STEP 1: OTP & NEW PASSWORD FORM ───
                  if (_currentStep == 1) ...[
                    // OTP Input
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: const TextStyle(
                        fontSize: 22,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '• • • • • •',
                        hintStyle: TextStyle(
                          letterSpacing: 8,
                          color: Colors.grey.shade400,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFE9E9E9),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Color(0xFF218358),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),

                    // Resend Link / Timer
                    const SizedBox(height: 10),
                    Center(
                      child: _resendCountdown > 0
                          ? Text(
                              'Resend code in ${_resendCountdown}s',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            )
                          : TextButton(
                              onPressed: _isResending ? null : _resendRecoveryCode,
                              child: _isResending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text(
                                      'Resend Code',
                                      style: TextStyle(
                                        color: Color(0xFF218358),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                            ),
                    ),

                    const SizedBox(height: 20),

                    // New Password
                    _buildInputField(
                      hint: 'Enter new password',
                      icon: Icons.lock_outline,
                      controller: _newPasswordController,
                      isPassword: true,
                      obscureText: _obscureNewPassword,
                      onToggleVisibility: () {
                        setState(() => _obscureNewPassword = !_obscureNewPassword);
                      },
                    ),

                    const SizedBox(height: 16),

                    // Confirm Password
                    _buildInputField(
                      hint: 'Confirm new password',
                      icon: Icons.lock_outline,
                      controller: _confirmPasswordController,
                      isPassword: true,
                      obscureText: _obscureConfirmPassword,
                      onToggleVisibility: () {
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),

                    const SizedBox(height: 30),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _resetPassword,
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
                                'Reset Password',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
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
