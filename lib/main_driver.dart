import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'screens/driver_ride_map_screen.dart';

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
  bool _online = false;
  String _walletBalance = '—';
  Timer? _ridesPollingTimer;
  Timer? _locationUpdateTimer;
  bool _loadingRides = false;
  bool _sendingLocation = false;
  String _locationStatus = 'A localização GPS ainda não foi enviada.';



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final savedStatus = await _authService.loadDriverAvailability();
      if (!mounted) return;
      setState(() => _online = savedStatus);
      await _loadWallet();

      // Recover an accepted/in-progress ride even if the driver is currently offline.
      // This keeps the active-ride card and its map available after a reload.
      await _recoverActiveRide();

      if (savedStatus) {
        await _loadAvailableRides();
        _startRidesPolling();
        _startLocationUpdates();
      }
    });
  }

  String get _activeRideStatus {
    switch (_activeRide?['status']?.toString()) {
      case 'ACEITA':
        return 'Corrida aceita';
      case 'EM_ANDAMENTO':
        return 'Em viagem';
      case 'CONCLUIDA':
        return 'Corrida concluída';
      case 'CANCELADA':
        return 'Corrida cancelada';
      default:
        return 'Sem corrida ativa';
    }
  }

  Future<void> _toggleOnline(bool value) async {
    if (value) {
      try {
        final permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permita o acesso à localização para ficar online.'),
            ),
          );
          return;
        }

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        await _api.setDriverAvailability(
          online: true,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
          ),
        );
        return;
      }
    } else {
      try {
        await _api.setDriverAvailability(online: false);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
          ),
        );
        return;
      }
    }

    await _authService.saveDriverAvailability(value);
    if (!mounted) return;
    setState(() {
      _online = value;
      if (!value) _incomingRides = [];
    });
    if (value) {
      await _loadAvailableRides();
      _startRidesPolling();
      _startLocationUpdates();
    } else {
      _stopRidesPolling();
      if (_activeRide != null) {
        _startLocationUpdates();
      } else {
        _stopLocationUpdates();
      }
    }
  }

  void _startLocationUpdates() {
    _stopLocationUpdates();
    if (!_online && _activeRide == null) return;

    _locationUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _sendCurrentLocation(),
    );
    _sendCurrentLocation();
  }

  void _stopLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
  }

  Future<void> _sendCurrentLocation() async {
    if ((!_online && _activeRide == null) || _sendingLocation) return;
    _sendingLocation = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('O serviço de localização do dispositivo está desativado.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permissão GPS recusada. Autorize a localização nas definições do navegador.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      // Keep location updates running during an active ride even if the driver
      // switched offline after accepting it. The backend allows location updates
      // for an active ride and must keep the driver's marker current on the map.
      if (!_online && _activeRide == null) return;
      if (_activeRide != null) {
        await _api.updateDriverLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } else if (_online) {
        await _api.setDriverAvailability(
          online: true,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _locationStatus =
            'GPS enviado às ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.';
      });
    } catch (error) {
      // Expose a useful diagnostic instead of silently hiding GPS/API failures.
      if (!mounted) return;
      setState(() {
        _locationStatus = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _sendingLocation = false;
    }
  }

  void _startRidesPolling() {
    _stopRidesPolling();
    if (!_online) return;
    _ridesPollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadAvailableRides(silent: true),
    );
  }

  void _stopRidesPolling() {
    _ridesPollingTimer?.cancel();
    _ridesPollingTimer = null;
  }

  Future<void> _loadWallet() async {
    try {
      final wallet = await _api.getWallet();
      if (!mounted) return;
      final balance = wallet['balance'];
      setState(() => _walletBalance = balance == null ? '—' : '$balance CFA');
    } catch (_) {
      // Keep the wallet unavailable rather than showing fabricated financial data.
    }
  }

  Future<void> _loadAvailableRides({bool silent = false}) async {
    if (!_online || _loadingRides) return;
    _loadingRides = true;
    try {
      // Recover an accepted/in-progress ride after app restart or reconnect.
      // While a ride is active, the server intentionally hides new requests.
      final activeRide = await _api.getActiveRide();
      if (!mounted) return;
      if (activeRide != null) {
        final activeRideId = activeRide['rideId']?.toString();
        final detailedRide = activeRideId != null && activeRideId.isNotEmpty
            ? await _api.getRide(activeRideId)
            : activeRide;
        if (!mounted) return;
        setState(() {
          _activeRide = detailedRide;
          _incomingRides = [];
        });
        return;
      }

      setState(() => _activeRide = null);
      final rides = await _api.getAvailableRides();
      if (!mounted) return;
      final hadNoRides = _incomingRides.isEmpty;
      setState(() => _incomingRides = rides);
      if (silent && hadNoRides && rides.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nova corrida disponível.')),
        );
      }
    } catch (error) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      _loadingRides = false;
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
      await _api.acceptRide(rideId);
      final accepted = await _api.getRide(rideId);
      if (!mounted) return;
      setState(() {
        _activeRide = accepted;
        _incomingRides.removeWhere((item) => item['rideId']?.toString() == rideId);
      });
      _stopRidesPolling();
      _startLocationUpdates();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrida aceita no servidor.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
      await _loadAvailableRides();
      if (!mounted) return;
    }
  }

  Future<void> _startRide() async {
    final rideId = _activeRide?['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) return;
    try {
      await _api.startRide(rideId);
      final result = await _api.getRide(rideId);
      if (!mounted) return;
      setState(() => _activeRide = result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }


  Future<void> _recoverActiveRide() async {
    try {
      final activeRide = await _api.getActiveRide();
      if (!mounted || activeRide == null) return;

      final rideId = activeRide['rideId']?.toString();
      final detailedRide = rideId != null && rideId.isNotEmpty
          ? await _api.getRide(rideId)
          : activeRide;
      if (!mounted) return;

      setState(() {
        _activeRide = detailedRide;
        _incomingRides = [];
      });
      _startLocationUpdates();
    } catch (_) {
      // A temporary network error should not block access to the dashboard.
    }
  }

  Future<void> _openRideMap(Map<String, dynamic> ride) async {
    final rideId = ride['rideId']?.toString();
    if (rideId == null || rideId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível identificar a corrida para abrir o mapa.')),
      );
      return;
    }

    // Fetch the full ride payload before opening the map so the map receives
    // the GeoJSON endpoints and the latest driver location.
    Map<String, dynamic> rideForMap = ride;
    try {
      rideForMap = await _api.getRide(rideId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível atualizar os dados da corrida: '
            '${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriverRideMapScreen(ride: rideForMap),
      ),
    );

    // Refresh the ride after returning from the map in case its status changed.
    if (!mounted) return;
    try {
      final refreshed = await _api.getRide(rideId);
      if (mounted) setState(() => _activeRide = refreshed);
    } catch (_) {
      // Keep the latest known ride data if the network is temporarily unavailable.
    }
  }

  Future<void> _completeRide() async {
    final ride = _activeRide;
    final rideId = ride?['rideId']?.toString();
    if (rideId == null || rideId.isEmpty || ride == null) return;

    final paymentMethod = ride['formaPagamento']?.toString().toUpperCase();
    if (paymentMethod != 'DINHEIRO') {
      final passenger = ride['passageiro'];
      final passengerName = passenger is Map
          ? (passenger['nome']?.toString().trim().isNotEmpty == true
              ? passenger['nome'].toString()
              : 'o passageiro')
          : 'o passageiro';
      final shouldCorrect = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar pagamento em dinheiro'),
          content: Text(
            'Esta corrida está registada com pagamento por '
            '${_paymentMethodLabel(paymentMethod)}. Se $passengerName pagou em dinheiro, '
            'corrija a forma de pagamento para poder concluir sem debitar a carteira.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Corrigir para dinheiro'),
            ),
          ],
        ),
      );
      if (shouldCorrect != true || !mounted) return;
    }

    try {
      if (paymentMethod != 'DINHEIRO') {
        await _api.correctRidePaymentToCash(rideId);
        final refreshed = await _api.getRide(rideId);
        if (!mounted) return;
        setState(() => _activeRide = refreshed);
      }
      final completion = await _api.completeRide(rideId);
      if (!mounted) return;
      setState(() {
        _activeRide = null;
        _incomingRides = [];
      });
      if (_online) {
        await _loadAvailableRides();
        if (!mounted) return;
        _startRidesPolling();
      }
      final debtStatus = completion['commissionDebtStatus']?.toString();
      final commission = completion['commission'];
      final message = debtStatus == 'PENDENTE'
          ? 'Corrida concluída. Comissão de $commission CFA registada como dívida pendente; a carteira não foi debitada.'
          : 'Corrida concluída. Pagamento em dinheiro registado.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
      try {
        final refreshed = await _api.getRide(rideId);
        if (mounted) setState(() => _activeRide = refreshed);
      } catch (_) {
        // Preserve the current ride data if refresh fails.
      }
    }
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'DINHEIRO':
        return 'dinheiro';
      case 'ORANGE_MONEY':
        return 'Orange Money';
      case 'MTN_MONEY':
        return 'MTN Money';
      default:
        return method?.isNotEmpty == true ? method! : 'a forma selecionada';
    }
  }

  Future<void> _logout() async {
    _stopRidesPolling();
    _stopLocationUpdates();
    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showNotifications() {
    const notifications = [
      'Novas corridas podem aparecer enquanto você estiver online.',
      'As atualizações da corrida são sincronizadas com o servidor.',
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
  void dispose() {
    _stopRidesPolling();
    _stopLocationUpdates();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeRide = _activeRide;

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
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _locationStatus.startsWith('GPS enviado')
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                  color: _locationStatus.startsWith('GPS enviado')
                      ? Colors.green
                      : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationStatus,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Hoje',
                  value: '—',
                  icon: Icons.account_balance_wallet_rounded,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Viagens',
                  value: '—',
                  icon: Icons.local_taxi_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            color: const Color(0xFFE0F5EA),
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Saldo da carteira'),
              subtitle: const Text('Carteira NhaCarro'),
              trailing: Text(
                _walletBalance,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
                              '${_incomingRides.length + (_activeRide != null ? 1 : 0)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                            label: 'Tempo médio',
                            value: '—'),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _MiniStat(
                            label: 'Receita',
                            value: '—'),
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
                          onPressed: _activeRide == null
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Aceite uma corrida para abrir o mapa do percurso.'),
                                    ),
                                  );
                                }
                              : () => _openRideMap(_activeRide!),
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
                    const Text(
                      'Corrida ativa',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Passageiro: ${(activeRide['passageiro'] is Map &&
                              (activeRide['passageiro'] as Map)['nome']?.toString().trim().isNotEmpty == true)
                          ? (activeRide['passageiro'] as Map)['nome'].toString()
                          : 'Nome indisponível'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (activeRide['formaPagamento'] != null) ...[
                      const SizedBox(height: 4),
                      Text('Pagamento: ${_paymentMethodLabel(activeRide['formaPagamento']?.toString().toUpperCase())}'),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openRideMap(activeRide),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Ver mapa da corrida'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Estado: $_activeRideStatus',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (activeRide['status'] == 'ACEITA')
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _startRide,
                          child: const Text('Iniciar viagem'),
                        ),
                      ),
                    if (activeRide['status'] == 'EM_ANDAMENTO')
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _completeRide,
                          child: const Text('Concluir viagem'),
                        ),
                      ),
                    if (activeRide['status'] == 'CONCLUIDA')
                      const Text('Corrida concluída no servidor.'),
                  ],
                ),
              ),
            ),
          ],
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
            onPressed: _online && _incomingRides.isNotEmpty
                ? () => _acceptRide(_incomingRides.first)
                : null,
            icon: const Icon(Icons.local_taxi_outlined),
            label: Text(
              _online
                  ? (_incomingRides.isEmpty
                      ? 'Aguardando corrida'
                      : 'Aceitar primeira corrida')
                  : 'Ficar online',
            ),
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
