import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';
import 'pages/home_page.dart';
import 'screen/welcome.dart';
import 'pages/login_page.dart';
import 'pages/signup_page.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: "https://jacgcceaxblwgdxaeaqk.supabase.co",
    anonKey:"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphY2djY2VheGJsd2dkeGFlYXFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4MzE4MDMsImV4cCI6MjA5NDQwNzgwM30.UQZJMdhEKQ2KqOmcvqFg8-JWBuR5b9XtjphzAnKeW6c"
  );
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TCAASlaughter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF218358)),
        useMaterial3: true,
        fontFamily: 'Roboto', // Professional Sans Serif
      ),
      home: const AuthGate(),
      routes: {
        '/WELCOME': (context) => const WelcomeScreen(),
        '/LOGIN': (context) => const LoginScreen(),
        '/SIGNUP': (context) => const SignupPages(),
        '/HOME': (context) => const HomeScreen(),
      },
    );
  }
}
