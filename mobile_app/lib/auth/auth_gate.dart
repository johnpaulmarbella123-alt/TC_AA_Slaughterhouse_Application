import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/home_page.dart';
import '../screen/welcome.dart';
import '../pages/login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Widget> _initialScreenFuture;

  @override
  void initState() {
    super.initState();
    _initialScreenFuture = _determineInitialScreen();
  }

  Future<Widget> _determineInitialScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasPreviouslyLoggedIn = prefs.getBool('has_previously_logged_in') ?? false;
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        // Actively verify against Supabase server that the user account still exists
        try {
          final userRes = await Supabase.instance.client.auth.getUser();
          if (userRes.user != null) {
            // User exists and session is valid -> Go directly to Home Page
            await prefs.setBool('has_previously_logged_in', true);
            return const HomeScreen();
          }
        } catch (_) {
          // Account was deleted in Supabase or token is invalid!
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (_) {}
          // Since they had an account, show Login page directly
          return const LoginScreen();
        }
      }

      // No active session:
      // 1. User had an account and logged out -> Show LoginScreen directly
      // 2. First-time fresh install -> Show WelcomeScreen (Get Started)
      if (hasPreviouslyLoggedIn) {
        return const LoginScreen();
      } else {
        return const WelcomeScreen();
      }
    } catch (_) {
      return const WelcomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _initialScreenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          return snapshot.data!;
        }
        return const Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: CircularProgressIndicator(
              color: Color(0xFF218358),
            ),
          ),
        );
      },
    );
  }
}
