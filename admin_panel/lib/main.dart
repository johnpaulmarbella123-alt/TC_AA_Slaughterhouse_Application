import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/hero_section.dart';
import 'screens/admin_shell.dart';
import 'pages/login_page.dart';
import 'services/app_settings_service.dart';
import 'widgets/dialog_blur_observer.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("dotenv loading error or file blocked by web server: $e");
  }

  const defaultUrl = 'https://jacgcceaxblwgdxaeaqk.supabase.co';
  const defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphY2djY2VheGJsd2dkeGFlYXFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4MzE4MDMsImV4cCI6MjA5NDQwNzgwM30.UQZJMdhEKQ2KqOmcvqFg8-JWBuR5b9XtjphzAnKeW6c';

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? defaultUrl;
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'] ?? defaultAnonKey;

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseKey,
  );

  // Initialize App Settings (loads persisted fees, roles, schedule, appearance, theme)
  await AppSettingsService.instance.initialize();

  // If staff session is active, ensure background admin auth session is active for DB operations
  final prefs = await SharedPreferences.getInstance();
  final keepLoggedIn = prefs.getBool('keepMeLoggedIn') ?? false;
  if (AppSettingsService.instance.hasActiveStaffSession) {
    await AppSettingsService.instance.ensureAdminAuthSession();
  } else if (!keepLoggedIn && Supabase.instance.client.auth.currentSession != null) {
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
          theme: AppTheme.lightTheme.copyWith(
            dialogTheme: const DialogThemeData(
              insetPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            ),
          ),
          darkTheme: AppTheme.darkTheme.copyWith(
            dialogTheme: const DialogThemeData(
              insetPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            ),
          ),
          themeMode: AppSettingsService.instance.themeMode,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final w = mq.size.width;
            final double scale = w < 600 ? 0.88 : (w < 900 ? 0.94 : 1.0);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          navigatorObservers: [DialogBlurObserver.instance],
          initialRoute: (Supabase.instance.client.auth.currentSession == null &&
                  !AppSettingsService.instance.hasActiveStaffSession)
              ? '/'
              : '/dashboard',
          routes: {
            '/': (context) => const HeroSection(),
            '/login': (context) => const LoginPage(),
            '/dashboard': (context) => const AdminShell(),
          },
        );
      },
    );
  }
}
