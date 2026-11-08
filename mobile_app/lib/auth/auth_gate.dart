import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/home_page.dart';
import '../screen/welcome.dart';

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
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        // Actively verify against Supabase server that the user account still exists
        try {
          final userRes = await Supabase.instance.client.auth.getUser();
          if (userRes.user != null) {
            // User exists and session is valid -> Go directly to Home Page
            return const HomeScreen();
          }
        } catch (_) {
          // Account was deleted in Supabase or token is invalid!
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (_) {}
          // Session is invalid -> Show WelcomeScreen (Get Started)
          return const WelcomeScreen();
        }
      }

      // No active session -> Always show WelcomeScreen (Get Started)
      return const WelcomeScreen();
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
