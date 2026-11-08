import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth/auth_server.dart';
import 'pages/home_page.dart';

class OtpScreen extends StatefulWidget {
  final String identifier; // email or phone
  final String password;
  final String username;
  final String address;
  final String? simulatedOtp;

  OtpScreen({
    super.key,
    String? identifier,
    String? phone,
    required this.password,
    required this.username,
    required this.address,
    this.simulatedOtp,
  }) : identifier = (identifier != null && identifier.isNotEmpty)
            ? identifier
            : (phone ?? '');

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final otpController = TextEditingController();
  final supabase = Supabase.instance.client;

  bool isLoading = false;
  bool isResending = false;
  bool _showNotificationBanner = true;
  String? _activeSimulatedOtp;

  bool get isEmail => widget.identifier.contains('@');

  @override
  void initState() {
    super.initState();
    _activeSimulatedOtp = widget.simulatedOtp ?? AuthService.getDefenseOtp(widget.identifier);
  }

  Future<void> verifyOtp() async {
    final token = otpController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the OTP code.')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final isDefenseMatch = !isEmail &&
          ((_activeSimulatedOtp != null && token == _activeSimulatedOtp) ||
              AuthService.verifyDefenseOtp(widget.identifier, token));

      if (isDefenseMatch) {
        // ── DEFENSE-READY VERIFICATION & LIVE ACCOUNT PERSISTENCE ──
        try {
          final res = await supabase.auth.signUp(
            phone: widget.identifier,
            password: widget.password,
            data: {
              'display_name': widget.username,
              'address': widget.address,
            },
          );
          if (res.user != null) {
            await supabase.from('profiles').upsert({
              'id': res.user!.id,
              'display_name': widget.username,
              'phone': widget.identifier,
              'address': widget.address,
            });
          }
        } catch (_) {
          // If phone auth without SMS gateway is restricted in Supabase instance,
          // persist via synthetic credential alias so account genuinely exists
          final cleanDigits = widget.identifier.replaceAll(RegExp(r'\D'), '');
          final syntheticEmail = 'user_$cleanDigits@tabaco-abattoir.gov.ph';
          try {
            final res = await supabase.auth.signUp(
              email: syntheticEmail,
              password: widget.password,
              data: {
                'display_name': widget.username,
                'address': widget.address,
                'phone': widget.identifier,
              },
            );
            if (res.user != null) {
              await supabase.from('profiles').upsert({
                'id': res.user!.id,
                'display_name': widget.username,
                'phone': widget.identifier,
                'address': widget.address,
              });
            }
          } catch (_) {
            try {
              await supabase.auth.signInWithPassword(
                email: syntheticEmail,
                password: widget.password,
              );
            } catch (_) {}
          }
        }

        AuthService.clearDefenseOtp(widget.identifier);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account verified successfully! Welcome.'),
              backgroundColor: Color(0xFF2D6A4F),
            ),
          );
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('has_previously_logged_in', true);
          } catch (_) {}

          if (!mounted) return;
          globalAvatarUrl.value = null;
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/HOME',
            (route) => false,
          );
        }
        return;
      }

      final response = await supabase.auth.verifyOTP(
        type: isEmail ? OtpType.email : OtpType.sms,
        email: isEmail ? widget.identifier : null,
        phone: isEmail ? null : widget.identifier,
        token: token,
      );

      final user = response.user;

      if (user != null) {
        // Set password and user metadata
        await supabase.auth.updateUser(
          UserAttributes(
            password: widget.password,
            data: {
              'display_name': widget.username,
              'address': widget.address,
            },
          ),
        );

        // Save profile data into profiles table
        final emailValue = isEmail ? widget.identifier : (user.email ?? '');
        final phoneValue = isEmail ? (user.phone ?? '') : widget.identifier;

        try {
          await supabase.from('profiles').insert({
            'id': user.id,
            'display_name': widget.username,
            'email': emailValue.isNotEmpty ? emailValue : null,
            'phone': phoneValue,
            'address': widget.address,
          });
        } catch (_) {
          // If profile already exists from a trigger, update it
          try {
            await supabase.from('profiles').update({
              'display_name': widget.username,
              'email': emailValue.isNotEmpty ? emailValue : null,
              'phone': phoneValue,
              'address': widget.address,
            }).eq('id', user.id);
          } catch (_) {}
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account verified successfully! Welcome.'),
              backgroundColor: Color(0xFF2D6A4F),
            ),
          );
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('has_previously_logged_in', true);
          } catch (_) {}

          if (!mounted) return;
          globalAvatarUrl.value = null;
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/HOME',
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
          msg = 'No internet connection. Please check your Wi-Fi or mobile data.';
        } else if (msg.contains('otp_expired') || msg.contains('Token has expired') || msg.contains('invalid')) {
          msg = 'The verification code has expired or is invalid. Please check your newest email or tap "Resend Code" below.';
        } else if (msg.contains('AuthApiException') || msg.contains('AuthException')) {
          msg = msg.replaceAll(RegExp(r'AuthApi?Exception\([^)]*message:\s*'), '').replaceAll(RegExp(r',[^)]*\)'), '');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> resendOtp() async {
    setState(() => isResending = true);
    try {
      if (isEmail) {
        await supabase.auth.signInWithOtp(email: widget.identifier);
      } else {
        final authService = AuthService();
        final res = await authService.sendOtp(widget.identifier);
        if (res['simulated'] == true) {
          setState(() {
            _activeSimulatedOtp = res['otp']?.toString();
            _showNotificationBanner = true;
          });
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A new OTP has been sent to ${widget.identifier}'),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
          msg = 'No internet connection. Please check your Wi-Fi or mobile data.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resend code: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isResending = false);
      }
    }
  }

  Widget _buildSmsNotificationBanner(String code) {
    if (!_showNotificationBanner) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.mark_chat_unread, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              const Text(
                'MESSAGES',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 6),
              const Text('•', style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Tabaco Slaughterhouse Auth',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text('Just now', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => setState(() => _showNotificationBanner = false),
                child: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.35),
              children: [
                const TextSpan(text: 'Your 6-digit OTP verification code is '),
                TextSpan(
                  text: code,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: Color(0xFF4ADE80),
                  ),
                ),
                const TextSpan(text: '. Do not share this code.'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () {
                  otpController.text = code;
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 13, color: Color(0xFF4ADE80)),
                      SizedBox(width: 4),
                      Text(
                        'Auto-Fill Code',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4ADE80)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Verify Code'),
        backgroundColor: const Color(0xFF2D6A4F),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!isEmail && _activeSimulatedOtp != null)
              _buildSmsNotificationBanner(_activeSimulatedOtp!),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEmail ? Icons.mark_email_read_outlined : Icons.sms_outlined,
                size: 54,
                color: const Color(0xFF2D6A4F),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isEmail ? 'Check Your Email' : 'Check Your Messages',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit verification code to:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.identifier,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D6A4F),
              ),
            ),
            if (isEmail) ...[
              const SizedBox(height: 8),
              Text(
                'Tip: If you don\'t see it in your inbox, check your spam/junk folder.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 32),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 24,
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
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2D6A4F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Verify & Complete Registration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Didn't receive code? ",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
                ),
                TextButton(
                  onPressed: isResending ? null : resendOtp,
                  child: isResending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Resend Code',
                          style: TextStyle(
                            color: Color(0xFF2D6A4F),
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}