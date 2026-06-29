import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tc_aa_slaughterhouse/pages/home_page.dart';
import 'package:tc_aa_slaughterhouse/screen/welcome.dart';


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // If the snapshot has data, check the session
        if (snapshot.hasData) {
          final session = snapshot.data!.session;
          if (session != null) {
            return const HomeScreen();
          }
        }
        
        // If not logged in, show Welcome Screen
        return const WelcomeScreen();
      },
    );
  }
}
