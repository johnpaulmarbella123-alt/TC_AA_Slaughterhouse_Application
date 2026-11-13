import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      final client = Supabase.instance.client;
      var session = client.auth.currentSession;

      // 1. If stored session exists from previous login
      if (session != null) {
        // If the access token has expired (default after 1 hour), refresh it using the refresh token
        if (session.isExpired) {
          try {
            final refreshRes = await client.auth.refreshSession();
            session = refreshRes.session;
          } catch (e) {
            debugPrint('Session refresh note on app open: $e');
            // Only sign out if the refresh token was explicitly revoked/invalidated by Supabase
            if (e is AuthException) {
              final msg = e.message.toLowerCase();
              if (msg.contains('invalid refresh token') ||
                  msg.contains('token not found') ||
                  msg.contains('user not found')) {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('is_customer_logged_in', false);
                  await client.auth.signOut();
                } catch (_) {}
                return const WelcomeScreen();
              }
            }
            // In case of transient network failure, don't destroy session; let user into Home
          }
        }

        // Verify current user is authenticated
        final user = client.auth.currentUser;
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_customer_logged_in', true);
          return const HomeScreen();
        }
      }

      // 2. Check persistent SharedPreferences flag
      final prefs = await SharedPreferences.getInstance();
      final wasLoggedIn = prefs.getBool('is_customer_logged_in') ?? false;
      if (wasLoggedIn && client.auth.currentUser != null) {
        return const HomeScreen();
      }

      // 3. User has no active session or explicitly logged out
      return const WelcomeScreen();
    } catch (e) {
      debugPrint('AuthGate determine screen error: $e');
      if (Supabase.instance.client.auth.currentUser != null) {
        return const HomeScreen();
      }
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
