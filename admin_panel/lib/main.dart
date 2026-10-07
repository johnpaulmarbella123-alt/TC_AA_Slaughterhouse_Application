import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/hero_section.dart';
import 'screens/admin_shell.dart';
import 'pages/login_page.dart';
import 'pages/signup_page.dart';
import 'services/app_settings_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Initialize App Settings (loads persisted fees, roles, schedule, appearance, theme)
  await AppSettingsService.instance.initialize();

  // If "Keep me logged in" was NOT checked on last login, sign out now
  // so the user must log in again on every app launch.
  final prefs = await SharedPreferences.getInstance();
  final keepLoggedIn = prefs.getBool('keepMeLoggedIn') ?? false;
  if (!keepLoggedIn && Supabase.instance.client.auth.currentSession != null) {
    await Supabase.instance.client.auth.signOut();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: AppSettingsService.instance.headerTitle,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: AppSettingsService.instance.themeMode,
          debugShowCheckedModeBanner: false,
          initialRoute: Supabase.instance.client.auth.currentSession == null ? '/' : '/dashboard',
          routes: {
            '/': (context) => const HeroSection(),
            '/login': (context) => const LoginPage(),
            '/signup': (context) => const SignupPage(),
            '/dashboard': (context) => const AdminShell(),
          },
        );
      },
    );
  }
}