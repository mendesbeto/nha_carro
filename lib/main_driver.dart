import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/ride_lifecycle_service.dart';

void main() {
  runApp(const NhaCarroDriverApp());
}

class NhaCarroDriverApp extends StatelessWidget {
  const NhaCarroDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NhaCarro Motorista',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B8F62)),
      ),
      home: const DriverHomeScreen(),
    );
  }
}

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final AuthService _authService = AuthService();
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _incomingRides = [];
  Map<String, dynamic>? _activeRide;
  bool _loadingRides = false;
  bool _online = false;

  final List<Map<String, dynamic>> _recentTrips = [
    {
      'route': 'Aeroporto → Bandim',
      'time': 'Hoje • 14:20',
      'amount': '3.500 CFA'
    },
    {
      'route': 'Mercado → Praia',
      'time': 'Ontem • 18:45',
      'amount': '2.800 CFA'
    },
    {'route': 'Centro → Casa', 'time': 'Seg • 08:10', 'amount': '1.900 CFA'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final savedStatus = await _authService.loadDriverAvailability();
      if (!mounted) return;
      setState(() => _online = savedStatus);
      if (savedStatus) await _loadAvailableRides();
    });
  }

  String get _activeRideStatus {
    final stage = RideLifecycleService.instance.currentStage;
    switch (stage) {
      case RideStage.accepted:
        return 'Corrida aceita';
      case RideStage.pickup:
        return 'A recolher passageiro';
      case RideStage.inTransit:
        return 'Em viagem';
      case RideStage.arrived:
        return 'Chegou ao destino';
      case RideStage.cancelled:
        return 'Corrida cancelada';
      case RideStage.requested:
        return 'Sem corrida ativa';
    }
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _online = value);
    await _authService.saveDriverAvailability(value);
    if (value) {
      await _loadAvailableRides();
    } else if (mounted) {
      setState(() => _incomingRides = []);
    }
  }

  Future<void> _loadAvailableRides() async {
    if (!_online) return;
    setState(() => _loadingRides = true);
    try {
      final rides = await _api.getAvailableRides();
      if (!mounted) return;
      setState(() => _incomingRides = rides);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loadingRides = false);
    }
  }

  Future<void> _acceptRide(Map<String, dynamic> ride) async {
    if (!_online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ative o modo online antes de aceitar uma corrida.')),
      );
      return;
    }
    final rideId = ride['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) return;

    try {
      final accepted = await _api.acceptRide(rideId);
      if (!mounted) return;
      setState(() {
        _activeRide = accepted;
        _incomingRides.removeWhere((item) => item['rideId']?.toString() == rideId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrida aceita no servidor.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
      await _loadAvailableRides();
    }
  }

  Future<void> _startRide() async {
    final rideId = _activeRide?['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) return;
    try {
      final result = await _api.startRide(rideId);
      if (!mounted) return;
      setState(() => _activeRide = result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _completeRide() async {
    final rideId = _activeRide?['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) return;
    try {
      final result = await _api.completeRide(rideId);
      if (!mounted) return;
      setState(() => _activeRide = result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrida concluída e liquidação processada.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _advanceRideStage(RideStage nextStage) {
    final currentRide = RideLifecycleService.instance.currentRide;
    if (currentRide == null) return;

    RideLifecycleService.instance.updateRideStage(nextStage);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Estado atualizado: $_activeRideStatus')),
    );
    setState(() {});
  }

  void _clearCurrentRide() {
    RideLifecycleService.instance.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Corrida finalizada e painel resetado.')),
    );
  }

  Future<void> _logout() async {
    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showNotifications() {
    const notifications = [
      'Nova corrida disponível perto de Bandim.',
      'Aisha P. confirmou o ponto de encontro.',
      'Você ganhou 150 CFA de bonificação hoje.',
    ];

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notificações'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: notifications
              .map((item) => ListTile(
                    leading: const Icon(Icons.notifications_active_outlined,
                        color: Color(0xFF0B8F62)),
                    title: Text(item),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeRide = _activeRide;
    final currentStage = RideLifecycleService.instance.currentStage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NhaCarro Motorista'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: _showNotifications,
              tooltip: 'Notificações',
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: _logout,
              tooltip: 'Sair',
              icon: const Icon(Icons.logout_rounded),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Olá, motorista!',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800)),
                        SizedBox(height: 6),
                        Text('Fique online para receber novas corridas.'),
                      ],
                    ),
                  ),
                  Switch(
                    value: _online,
                    onChanged: _toggleOnline,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Hoje',
                  value: '1.250 CFA',
                  icon: Icons.account_balance_wallet_rounded,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Viagens',
                  value: '4',
                  icon: Icons.local_taxi_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Card(
            color: Color(0xFFE0F5EA),
            child: ListTile(
              leading: Icon(Icons.account_balance_wallet_outlined),
              title: Text('Saldo da carteira'),
              subtitle: Text('Carteira NhaCarro'),
              trailing: Text(
                '5.000 CFA',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resumo do dia',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          label: 'Disponível',
                          value: _online ? 'Online' : 'Offline',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniStat(
                          label: 'Próximas',
                          value:
                              '${_incomingRides.length + (RideLifecycleService.instance.currentRide != null ? 1 : 0)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                            label: 'Tempo médio',
                            value: _online ? '11 min' : '—'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniStat(
                            label: 'Receita',
                            value: _online ? '1.250 CFA' : '0 CFA'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Ações rápidas',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.route_outlined,
                          label: 'Ver rota',
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Rota para Bandim aberta no painel do motorista.')),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.check_circle_outline,
                          label: 'Aceitar',
                          onPressed: () {
                            if (_incomingRides.isEmpty) return;
                            _acceptRide(_incomingRides.first);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (activeRide != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Corrida ativa: ${activeRide['passenger']}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text('Origem: ${activeRide['from']}'),
                    const SizedBox(height: 4),
                    Text('Destino: ${activeRide['to']}'),
                    const SizedBox(height: 8),
                    Text('Estado: $_activeRideStatus',
                        style: const TextStyle(
                            color: Color(0xFF0B8F62),
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StageChip(
                          label: 'Aceitar',
                          enabled: currentStage == RideStage.accepted,
                          onPressed: () =>
                              _advanceRideStage(RideStage.accepted),
                        ),
                        _StageChip(
                          label: 'Embarque',
                          enabled: currentStage == RideStage.pickup,
                          onPressed: () => _advanceRideStage(RideStage.pickup),
                        ),
                        _StageChip(
                          label: 'Em viagem',
                          enabled: currentStage == RideStage.inTransit,
                          onPressed: () =>
                              _advanceRideStage(RideStage.inTransit),
                        ),
                        _StageChip(
                          label: 'Chegou',
                          enabled: currentStage == RideStage.arrived,
                          onPressed: () => _advanceRideStage(RideStage.arrived),
                        ),
                      ],
                    ),
                    if (currentStage == RideStage.arrived ||
                        currentStage == RideStage.cancelled) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _clearCurrentRide,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Limpar corrida'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Últimas corridas',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  ..._recentTrips.map((trip) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDDF5EA),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.local_taxi_rounded,
                                  size: 18, color: Color(0xFF0B8F62)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(trip['route'] as String,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(trip['time'] as String,
                                      style: const TextStyle(
                                          color: Colors.black54, fontSize: 12)),
                                ],
                              ),
                            ),
                            Text(trip['amount'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Corridas disponíveis',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_incomingRides.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF0B8F62)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _online
                            ? 'Nenhuma corrida disponível no momento. Vamos aguardar novas solicitações.'
                            : 'Ative o modo online para receber novas solicitações de viagem.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._incomingRides.map((ride) => _RideRequestCard(
                  ride: ride,
                  onAccept: () => _acceptRide(ride),
                )),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _online
                ? () {
                    if (_incomingRides.isEmpty) return;
                    _acceptRide(_incomingRides.first);
                  }
                : null,
            icon: const Icon(Icons.local_taxi_outlined),
            label: Text(_online ? 'Aceitar primeira corrida' : 'Ficar online'),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: enabled,
      onSelected: (_) => onPressed(),
      selectedColor: const Color(0xFFE0F5EA),
      labelStyle: TextStyle(
        color: enabled ? const Color(0xFF0B8F62) : Colors.black87,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFDDF5EA),
                  ),
                  child: Icon(icon, color: const Color(0xFF0B8F62), size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _RideRequestCard extends StatelessWidget {
  const _RideRequestCard({required this.ride, required this.onAccept});

  final Map<String, dynamic> ride;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFDDF5EA),
                  child: Icon(Icons.person, color: Color(0xFF0B8F62)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ride['passenger'],
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('Em ${ride['time']} • ${ride['fare']}',
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Nova',
                      style: TextStyle(
                          color: Color(0xFF0B8F62),
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.trip_origin,
                    color: Color(0xFF0B8F62), size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(ride['from'], overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on,
                    color: Color(0xFFE39A1E), size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(ride['to'], overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B8F62),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Aceitar corrida'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
