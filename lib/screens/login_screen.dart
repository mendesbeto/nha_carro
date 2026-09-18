import 'package:flutter/material.dart';

import '../main_driver.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'home_passenger_screen.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = AuthService();
  UserRole _role = UserRole.passenger;
  bool _loading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() => _loading = true);

    try {
      final response = await ApiService().login(email: email, password: password);

      if (!mounted) return;

      final role = (response['role'] as String?) ?? 'passenger';
      final nextRole = switch (role) {
        'driver' => UserRole.driver,
        'admin' => UserRole.admin,
        _ => UserRole.passenger,
      };

      await _auth.saveSession(
        role: nextRole == UserRole.admin ? 'admin' : (role == 'driver' ? 'driver' : 'passenger'),
        name: (response['name'] as String?) ??
            (nextRole == UserRole.admin
                ? 'Administrador'
                : nextRole == UserRole.passenger
                    ? 'Passageiro'
                    : 'Motorista'),
        email: (response['email'] as String?) ?? email,
        accessToken: (response['access_token'] as String?) ?? '',
        refreshToken: (response['refresh_token'] as String?) ?? '',
        rememberMe: _rememberMe,
      );

      setState(() => _loading = false);

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => switch (nextRole) {
            UserRole.passenger => const HomePassengerScreen(),
            UserRole.driver => const DriverHomeScreen(),
            UserRole.admin => const AdminScreen(),
          },
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um e-mail válido para recuperar a senha.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar senha'),
        content: Text('Enviámos um link de recuperação para $email.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDDF5EA),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.lock_open_rounded, size: 30, color: Color(0xFF0B8F62)),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Bem-vindo de volta',
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Entre com a sua conta para continuar.',
                            style: TextStyle(fontSize: 15, color: Colors.black54),
                          ),
                          const SizedBox(height: 22),
                          SegmentedButton<UserRole>(
                            segments: const [
                              ButtonSegment<UserRole>(
                                value: UserRole.passenger,
                                label: Text('Passageiro'),
                                icon: Icon(Icons.person),
                              ),
                              ButtonSegment<UserRole>(
                                value: UserRole.driver,
                                label: Text('Motorista'),
                                icon: Icon(Icons.drive_eta),
                              ),
                              ButtonSegment<UserRole>(
                                value: UserRole.admin,
                                label: Text('Admin'),
                                icon: Icon(Icons.admin_panel_settings_outlined),
                              ),
                            ],
                            selected: {_role},
                            onSelectionChanged: (newSelection) {
                              setState(() => _role = newSelection.first);
                            },
                          ),
                          const SizedBox(height: 14),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) => value == null || !value.contains('@')
                                ? 'Informe um e-mail válido.'
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'E-mail',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            validator: (value) => value == null || value.length < 6
                                ? 'A senha deve ter pelo menos 6 caracteres.'
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (value) => setState(() => _rememberMe = value ?? true),
                              ),
                              const Expanded(child: Text('Lembrar-me')),
                              TextButton(
                                onPressed: _resetPassword,
                                child: const Text('Esqueci-me da senha'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _login,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(_loading ? 'Entrando...' : 'Entrar'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0B8F62),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const RegistrationRoleSelectionScreen(),
                                  ),
                                );
                              },
                              child: const Text('Criar uma conta'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
