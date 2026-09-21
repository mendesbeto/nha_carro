import 'package:flutter/material.dart';

import 'main_driver.dart';
import 'screens/admin_screen.dart';
import 'screens/home_passenger_screen.dart';
import 'screens/registration_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/password_recovery_link_service.dart';
import 'screens/reset_password_screen.dart';

void main() {
  runApp(const NhaCarroApp());
}

class NhaCarroApp extends StatefulWidget {
  const NhaCarroApp({super.key});

  @override
  State<NhaCarroApp> createState() => _NhaCarroAppState();
}

class _NhaCarroAppState extends State<NhaCarroApp> {
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();
  final PasswordRecoveryLinkService _recoveryLinks =
      PasswordRecoveryLinkService();

  Future<Widget> _initialScreen() async {
    final auth = AuthService();
    final session = await auth.loadSession();
    final role = session['role'];

    if (role == null) {
      return const RegistrationRoleSelectionScreen();
    }

    try {
      final user = await ApiService().me();
      final serverRole = user['role'] as String?;
      if (serverRole == 'driver') return const DriverHomeScreen();
      if (serverRole == 'passenger') return const HomePassengerScreen();
      if (serverRole == 'admin') return const AdminScreen();
    } catch (_) {
      await auth.clearSession();
    }

    return const RegistrationRoleSelectionScreen();
  }

  @override
  void initState() {
    super.initState();
    _recoveryLinks.listen(_handleRecoveryLink);
    _loadInitialRecoveryLink();
  }

  Future<void> _loadInitialRecoveryLink() async {
    final uri = await _recoveryLinks.initialLink();
    if (uri != null) _handleRecoveryLink(uri);
  }

  void _handleRecoveryLink(Uri uri) {
    final accessToken = PasswordRecoveryLinkService.accessTokenFrom(uri);
    if (accessToken == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;

      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(accessToken: accessToken),
        ),
      );
    });
  }

  @override
  void dispose() {
    _recoveryLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0B8F62);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'NhaCarro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          surface: const Color(0xFFF8FAF9),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAF9),
        fontFamily: 'sans',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
      home: FutureBuilder<Widget>(
        future: _initialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          return snapshot.data ?? const RegistrationRoleSelectionScreen();
        },
      ),
    );
  }
}
