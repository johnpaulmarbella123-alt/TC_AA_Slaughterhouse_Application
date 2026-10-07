import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tc_aa_slaughterhouse/screen/welcome.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    // If the user already has an active session, auto-navigate to Home
    // after showing the Welcome screen briefly.
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      // Small delay so the Welcome screen is visible first
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/HOME', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always show the Welcome / Get Started screen first
    return const WelcomeScreen();
  }
}
