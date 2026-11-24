import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth/auth_gate.dart';
import 'pages/home_page.dart';
import 'screen/welcome.dart';
import 'pages/login_page.dart';
import 'pages/forgot_password_page.dart';
import 'pages/signup_page.dart';
import 'screen/how_it_works.dart';
import 'services/connectivity_service.dart';
import 'services/livestock_fee_service.dart';
import 'widgets/connectivity_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('dotenv load warning: $e');
  }
  runApp(const MyApp());
}

SupabaseClient get supabase => Supabase.instance.client;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _connectivity = ConnectivityService.instance;
  bool _isSupabaseInitialized = false;
  bool _isBootstrapping = true;
  String _loadingStatus = 'Checking internet connection...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivity.isConnected.addListener(_handleConnectivityChanged);
    _connectivity.startMonitoring();
    _bootstrapApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity.isConnected.removeListener(_handleConnectivityChanged);
    _connectivity.stopMonitoring();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connectivity.checkNow(silent: true);
    }
  }

  void _handleConnectivityChanged() {
    // If the app launched offline and internet just came back, complete bootstrap automatically
    if (_connectivity.isConnected.value && !_isSupabaseInitialized && !_isBootstrapping) {
      _bootstrapApp();
    }
  }

  Future<void> _bootstrapApp() async {
    if (mounted) {
      setState(() {
        _isBootstrapping = true;
        _loadingStatus = 'Checking internet connection...';
      });
    }

    final online = await _connectivity.checkNow();
    if (!online) {
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
        });
      }
      return;
    }

    try {
      if (!_isSupabaseInitialized) {
        if (mounted) {
          setState(() => _loadingStatus = 'Connecting to Tabaco City Slaughterhouse...');
        }
        const fallbackUrl = 'https://jacgcceaxblwgdxaeaqk.supabase.co';
        const fallbackAnonKey =
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphY2djY2VheGJsd2dkeGFlYXFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4MzE4MDMsImV4cCI6MjA5NDQwNzgwM30.UQZJMdhEKQ2KqOmcvqFg8-JWBuR5b9XtjphzAnKeW6c';

        final url = dotenv.env['SUPABASE_URL'] ?? fallbackUrl;
        final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? fallbackAnonKey;

        await Supabase.initialize(url: url, anonKey: anonKey);
        _isSupabaseInitialized = true;
      }

      if (mounted) {
        setState(() => _loadingStatus = 'Loading slaughterhouse services...');
      }
      await LivestockFeeService.instance.initialize();
    } catch (e) {
      debugPrint('App bootstrap error: $e');
      await _connectivity.checkNow();
    } finally {
      if (mounted) {
        setState(() => _isBootstrapping = false);
      }
    }
  }

  Future<void> _onRetryConnection() async {
    final online = await _connectivity.checkNow();
    if (online && !_isSupabaseInitialized) {
      await _bootstrapApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TCAASlaughter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF218358)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: _connectivity.isConnected,
          builder: (context, isConnected, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _connectivity.isChecking,
              builder: (context, isChecking, _) {
                return Stack(
                  children: [
                    if (child != null) child,
                    if (!isConnected)
                      Positioned.fill(
                        child: NoInternetOverlay(
                          isChecking: isChecking,
                          onRetry: _onRetryConnection,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
      home: (_isBootstrapping || !_isSupabaseInitialized)
          ? AppStartupLoadingView(statusText: _loadingStatus)
          : const AuthGate(),
      routes: {
        '/WELCOME': (context) => const WelcomeScreen(),
        '/LOGIN': (context) => const LoginScreen(),
        '/FORGOT_PASSWORD': (context) => const ForgotPasswordScreen(),
        '/SIGNUP': (context) => const SignupPages(),
        '/HOME': (context) => const HomeScreen(),
        '/HOW_IT_WORKS': (context) => const HowItWorksScreen(),
      },
    );
  }
}
