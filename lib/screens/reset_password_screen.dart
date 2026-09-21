import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String accessToken;

  const ResetPasswordScreen({super.key, required this.accessToken});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      await ApiService().resetPassword(
        token: widget.accessToken,
        password: _password.text,
        passwordConfirmation: _confirmation.text,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Palavra-passe alterada'),
          content: const Text(
            'A sua palavra-passe foi alterada com sucesso. '
            'Por segurança, as sessões anteriores foram encerradas.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ir para o login'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova palavra-passe')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Defina uma nova palavra-passe',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Escolha uma palavra-passe com pelo menos 8 caracteres.',
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  validator: (value) => value == null || value.length < 8
                      ? 'A palavra-passe deve ter pelo menos 8 caracteres.'
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Nova palavra-passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmation,
                  obscureText: _obscure,
                  validator: (value) => value != _password.text
                      ? 'As palavras-passe não coincidem.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar palavra-passe',
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _reset,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      _loading
                          ? 'A atualizar...'
                          : 'Alterar palavra-passe',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
