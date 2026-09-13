import 'package:flutter/material.dart';

import '../main_driver.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'home_passenger_screen.dart';
import 'login_screen.dart';

enum UserRole { passenger, driver, admin }

class RegistrationRoleSelectionScreen extends StatefulWidget {
  const RegistrationRoleSelectionScreen({super.key});

  @override
  State<RegistrationRoleSelectionScreen> createState() =>
      _RegistrationRoleSelectionScreenState();
}

class _RegistrationRoleSelectionScreenState
    extends State<RegistrationRoleSelectionScreen> {
  UserRole? _selectedRole;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDF5EA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded, size: 30, color: Color(0xFF0B8F62)),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Crie a sua conta',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Escolha o perfil que melhor se encaixa no seu uso do NhaCarro.',
                          style: TextStyle(fontSize: 15, color: Colors.black.withValues(alpha: 0.65)),
                        ),
                        const SizedBox(height: 24),
                        _RoleCard(
                          title: 'Passageiro',
                          subtitle: 'Pedir viagens e acompanhar deslocações em Bissau.',
                          icon: Icons.person_rounded,
                          isSelected: _selectedRole == UserRole.passenger,
                          onTap: () => setState(() => _selectedRole = UserRole.passenger),
                        ),
                        const SizedBox(height: 14),
                        _RoleCard(
                          title: 'Motorista',
                          subtitle: 'Receber corridas e gerir a sua disponibilidade.',
                          icon: Icons.drive_eta_rounded,
                          isSelected: _selectedRole == UserRole.driver,
                          onTap: () => setState(() => _selectedRole = UserRole.driver),
                        ),
                        const SizedBox(height: 14),
                        _RoleCard(
                          title: 'Admin',
                          subtitle: 'Acompanhar operações, métricas e suporte da plataforma.',
                          icon: Icons.admin_panel_settings_rounded,
                          isSelected: _selectedRole == UserRole.admin,
                          onTap: () => setState(() => _selectedRole = UserRole.admin),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            onPressed: _selectedRole == null
                                ? null
                                : () async {
                                    if (_selectedRole == UserRole.admin) {
                                      final auth = AuthService();
                                      await auth.saveSession(
                                        role: 'admin',
                                        name: 'Administrador',
                                        email: 'admin@nhacarro.com',
                                        rememberMe: true,
                                      );
                                      if (!context.mounted) return;
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const AdminScreen(),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => RegistrationFormScreen(role: _selectedRole!),
                                      ),
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  );
                                },
                                child: const Text('Já tenho conta'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const HomePassengerScreen(),
                                    ),
                                  );
                                },
                                child: const Text('Entrar sem conta'),
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? const Color(0xFF0B8F62) : Colors.grey.shade200;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? const Color(0xFFE7F8F0) : Colors.white,
          border: Border.all(color: color, width: isSelected ? 1.6 : 1),
          boxShadow: [
            if (isSelected)
              const BoxShadow(
                color: Color(0x1A0B8F62),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : const Color(0xFF0B8F62), size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? const Color(0xFF0B8F62) : Colors.black45,
            ),
          ],
        ),
      ),
    );
  }
}

class RegistrationFormScreen extends StatefulWidget {
  const RegistrationFormScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<RegistrationFormScreen> createState() => _RegistrationFormScreenState();
}

class _RegistrationFormScreenState extends State<RegistrationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _plateController = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _vehicleController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  String get _screenTitle => widget.role == UserRole.passenger ? 'Cadastro de passageiro' : 'Cadastro de motorista';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aceite os termos para continuar com o cadastro.')),
      );
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não coincidem.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await ApiService().registerUser(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: widget.role.name,
        vehicle: widget.role == UserRole.driver ? _vehicleController.text.trim() : null,
        plate: widget.role == UserRole.driver ? _plateController.text.trim() : null,
      );

      if (!mounted) return;

      await _auth.saveSession(
        role: (response['role'] as String?) ?? widget.role.name,
        name: (response['name'] as String?) ?? _nameController.text.trim(),
        email: (response['email'] as String?) ?? _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        rememberMe: true,
      );

      setState(() => _loading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.role == UserRole.passenger
                ? 'Cadastro de passageiro realizado com sucesso!'
                : 'Cadastro de motorista realizado com sucesso!',
          ),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => widget.role == UserRole.passenger ? const HomePassengerScreen() : const DriverHomeScreen(),
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

  @override
  Widget build(BuildContext context) {
    final isPassenger = widget.role == UserRole.passenger;

    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              Text(
                isPassenger
                    ? 'Preencha seus dados para começar a solicitar viagens.'
                    : 'Cadastre-se para receber corridas e gerir o seu perfil.',
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              _buildField('Nome completo', Icons.person, _nameController, validator: (value) => value == null || value.trim().isEmpty ? 'Informe o nome completo.' : null),
              const SizedBox(height: 14),
              _buildField('Telefone', Icons.phone, _phoneController, keyboardType: TextInputType.phone, validator: (value) => value == null || value.trim().length < 8 ? 'Telefone inválido.' : null),
              const SizedBox(height: 14),
              _buildField('E-mail', Icons.email, _emailController, keyboardType: TextInputType.emailAddress, validator: (value) => value == null || !value.contains('@') ? 'Informe um e-mail válido.' : null),
              const SizedBox(height: 14),
              _buildPasswordField(
                label: 'Senha',
                controller: _passwordController,
                obscureText: _obscurePassword,
                onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                validator: (value) => value == null || value.length < 6 ? 'A senha deve ter pelo menos 6 caracteres.' : null,
              ),
              const SizedBox(height: 14),
              _buildPasswordField(
                label: 'Confirmar senha',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                onToggleVisibility: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                validator: (value) => value == null || value.isEmpty ? 'Confirme a senha.' : null,
              ),
              if (!isPassenger) ...[
                const SizedBox(height: 14),
                _buildField('Veículo', Icons.local_taxi, _vehicleController, validator: (value) => value == null || value.trim().isEmpty ? 'Informe o tipo do veículo.' : null),
                const SizedBox(height: 14),
                _buildField('Matrícula', Icons.confirmation_number_rounded, _plateController, validator: (value) => value == null || value.trim().isEmpty ? 'Informe a matrícula.' : null),
              ],
              const SizedBox(height: 18),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Aceito os termos e política de privacidade do NhaCarro.'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 26),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_loading ? 'A guardar...' : 'Criar conta'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B8F62),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    IconData icon,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF0B8F62)),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF0B8F62)),
        suffixIcon: IconButton(
          onPressed: onToggleVisibility,
          icon: Icon(
            obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: const Color(0xFF0B8F62),
          ),
        ),
      ),
    );
  }
}
