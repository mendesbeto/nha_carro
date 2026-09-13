import 'package:flutter/material.dart';

import 'main_driver.dart';
import 'screens/admin_screen.dart';
import 'screens/home_passenger_screen.dart';
import 'screens/registration_screen.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const NhaCarroApp());
}

class NhaCarroApp extends StatelessWidget {
  const NhaCarroApp({super.key});

  Future<Widget> _initialScreen() async {
    final session = await AuthService().loadSession();
    final role = session['role'];

    if (role == 'driver') {
      return const DriverHomeScreen();
    }
    if (role == 'passenger') {
      return const HomePassengerScreen();
    }
    if (role == 'admin') {
      return const AdminScreen();
    }
    return const RegistrationRoleSelectionScreen();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0B8F62);

    return MaterialApp(
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
