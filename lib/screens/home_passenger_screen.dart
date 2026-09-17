import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/ride_request.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/ride_history_service.dart';
import '../services/ride_lifecycle_service.dart';
import 'login_screen.dart';
import 'ride_tracking_screen.dart';
import 'support_screen.dart';

class HomePassengerScreen extends StatefulWidget {
  const HomePassengerScreen({super.key});

  @override
  State<HomePassengerScreen> createState() => _HomePassengerScreenState();
}

class _HomePassengerScreenState extends State<HomePassengerScreen> {
  final _destinationController = TextEditingController();
  final _api = ApiService();
  final _authService = AuthService();
  final _historyService = RideHistoryService();
  final _bissauLocation = const LatLng(11.8811, -15.6177);
  final _rideLifeCycle = RideLifecycleService.instance;
  final List<Map<String, dynamic>> _walletTransactions = [];
  GoogleMapController? _mapController;
  LatLng _currentLocation = const LatLng(11.8811, -15.6177);
  RideCategory _category = RideCategory.taxi;
  PaymentMethod _payment = PaymentMethod.cash;
  bool _loading = false;
  bool _locationLoading = false;
  bool _rideAccepted = false;
  int _selectedTab = 0;
  int _walletBalance = 5000;
  String _profileName = 'Marta D.';
  List<String> _favoritePlaces = const [
    'Aeroporto',
    'Mercado de Bandim',
    'Casa',
    'Praia de Bissau',
    'Bairro Pindjiguiti',
  ];
  String _profileEmail = 'marta@gmail.com';
  String _profilePhone = '+245 555 123 456';
  String _profileAddress = 'Rua de Bissau, Bairro Pindjiguiti';

  String get _rideStatusMessage {
    final stage = _rideLifeCycle.currentRide?['stage'] as String?;
    switch (stage) {
      case 'accepted':
        return 'Motorista aceitou a sua viagem. Acompanhe a corrida.';
      case 'pickup':
        return 'O motorista está a caminho para o ponto de encontro.';
      case 'inTransit':
        return 'A sua viagem está em andamento para o destino.';
      case 'arrived':
        return 'O motorista chegou ao destino. A viagem foi concluída.';
      case 'cancelled':
        return 'Viagem cancelada. A sua reserva foi anulada e o reembolso foi processado.';
      default:
        return 'Motorista aceitou a sua viagem. Acompanhe a corrida.';
    }
  }

  int get _estimatedFare {
    final baseByCategory = switch (_category) {
      RideCategory.taxi => 2500,
      RideCategory.confort => 3500,
      RideCategory.moto => 1800,
    };

    final destination = _destinationController.text.trim();
    final destinationBoost = destination.isEmpty
        ? 0
        : destination.length > 15
            ? 550
            : 250;

    return baseByCategory + destinationBoost;
  }

  String get _estimatedTravelTime {
    final categoryTime = switch (_category) {
      RideCategory.taxi => 12,
      RideCategory.confort => 8,
      RideCategory.moto => 6,
    };

    final destination = _destinationController.text.trim();
    final extraMinutes = destination.isEmpty
        ? 0
        : destination.length > 12
            ? 4
            : 2;

    return '${categoryTime + extraMinutes} min';
  }

  final List<Map<String, dynamic>> _tripHistory = [
    {
      'route': 'Aeroporto → Bandim',
      'date': 'Hoje • 14:20',
      'status': 'Concluída',
      'fare': '2.500 CFA'
    },
    {
      'route': 'Mercado → Praia',
      'date': 'Ontem • 18:45',
      'status': 'Concluída',
      'fare': '3.200 CFA'
    },
    {
      'route': 'Casa → Bairro',
      'date': 'Seg • 08:10',
      'status': 'Agendada',
      'fare': '1.800 CFA'
    },
  ];

  @override
  void initState() {
    super.initState();
    _rideLifeCycle.acceptedRideStream.listen((ride) async {
      if (!mounted) return;
      final stage = ride?['stage'] as String?;
      final terminalStage =
          stage == RideStage.arrived.name || stage == RideStage.cancelled.name;

      if (stage == RideStage.arrived.name) {
        final route =
            '${ride?['from'] ?? 'Origem'} → ${ride?['to'] ?? 'Destino'}';
        final fare = (ride?['fare'] as String?) ?? '2.500 CFA';
        await _historyService.addCompletedRide(route: route, fare: fare);
        await _loadHistory();
      }

      if (terminalStage) {
        _rideLifeCycle.clear();
      }

      setState(() => _rideAccepted = !terminalStage && ride != null);
    });
    final currentRide = _rideLifeCycle.currentRide;
    if (currentRide != null) {
      _rideAccepted = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestCurrentLocation();
      _loadHistory();
      _loadProfile();
      _loadPreferredPayment();
      _loadFavoritePlaces();
    });
  }

  Future<void> _loadFavoritePlaces() async {
    final savedPlaces = await _authService.loadFavoritePlaces();
    if (!mounted) return;

    setState(() {
      _favoritePlaces = savedPlaces.isEmpty
          ? const [
              'Aeroporto',
              'Mercado de Bandim',
              'Casa',
              'Praia de Bissau',
              'Bairro Pindjiguiti',
            ]
          : savedPlaces;
    });
  }

  Future<void> _saveFavoritePlace(String place) async {
    final trimmed = place.trim();
    if (trimmed.isEmpty) return;

    final places = <String>{..._favoritePlaces, trimmed}.toList();
    await _authService.saveFavoritePlaces(places);
    if (!mounted) return;
    setState(() => _favoritePlaces = places);
  }

  Future<void> _removeFavoritePlace(String place) async {
    final places = _favoritePlaces.where((item) => item != place).toList();
    await _authService.saveFavoritePlaces(places);
    if (!mounted) return;
    setState(() => _favoritePlaces = places);
  }

  Future<void> _loadPreferredPayment() async {
    final preferredPayment = await _authService.loadPreferredPayment();
    if (!mounted) return;

    switch (preferredPayment) {
      case 'cash':
        _payment = PaymentMethod.cash;
        break;
      case 'orangeMoney':
        _payment = PaymentMethod.orangeMoney;
        break;
      case 'mtnMoney':
        _payment = PaymentMethod.mtnMoney;
        break;
      default:
        _payment = PaymentMethod.orangeMoney;
    }
    setState(() {});
  }

  Future<void> _updatePreferredPayment(PaymentMethod payment) async {
    await _authService.savePreferredPayment(payment.name);
    setState(() => _payment = payment);
  }

  Future<void> _loadProfile() async {
    final session = await _authService.loadSession();
    if (!mounted) return;
    setState(() {
      _profileName = session['name'] ?? _profileName;
      _profileEmail = session['email'] ?? _profileEmail;
      _profilePhone = session['phone'] ?? _profilePhone;
      _profileAddress = session['address'] ?? _profileAddress;
    });
  }

  Future<void> _loadHistory() async {
    final history = await _historyService.loadHistory();
    final wallet = await _historyService.loadWalletBalance();
    final transactions = await _historyService.loadTransactions();
    if (!mounted) return;
    setState(() {
      _tripHistory
        ..clear()
        ..addAll(history.isNotEmpty
            ? history
            : [
                {
                  'route': 'Aeroporto → Bandim',
                  'date': 'Hoje • 14:20',
                  'status': 'Concluída',
                  'fare': '2.500 CFA'
                },
                {
                  'route': 'Mercado → Praia',
                  'date': 'Ontem • 18:45',
                  'status': 'Concluída',
                  'fare': '3.200 CFA'
                },
                {
                  'route': 'Casa → Bairro',
                  'date': 'Seg • 08:10',
                  'status': 'Agendada',
                  'fare': '1.800 CFA'
                },
              ]);
      _walletBalance = wallet;
      _walletTransactions
        ..clear()
        ..addAll(transactions.isNotEmpty
            ? transactions
            : [
                {
                  'label': 'Carregamento de carteira',
                  'amount': 1500,
                  'type': 'credit',
                  'date': 'Hoje • 09:15'
                },
                {
                  'label': 'Pagamento da viagem',
                  'amount': -2500,
                  'type': 'debit',
                  'date': 'Ontem • 18:50'
                },
              ]);
    });
  }

  Future<void> _topUpWallet() async {
    final controller = TextEditingController();
    final amount = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Carregar carteira'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Valor em CFA',
            prefixIcon: Icon(Icons.account_balance_wallet_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(context)
                  .pop(parsed != null && parsed > 0 ? parsed : null);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (amount == null || !mounted) return;

    await _historyService.addWalletCredit(amount);
    await _loadHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Carteira carregada com $amount CFA')),
    );
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _profileName);
    final emailController = TextEditingController(text: _profileEmail);
    final phoneController = TextEditingController(text: _profilePhone);
    final addressController = TextEditingController(text: _profileAddress);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar perfil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Endereço'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final session = await _authService.loadSession();
    await _authService.saveSession(
      role: session['role'] ?? 'passenger',
      name: nameController.text.trim().isNotEmpty
          ? nameController.text.trim()
          : _profileName,
      email: emailController.text.trim().isNotEmpty
          ? emailController.text.trim()
          : _profileEmail,
      phone: phoneController.text.trim().isNotEmpty
          ? phoneController.text.trim()
          : _profilePhone,
      address: addressController.text.trim().isNotEmpty
          ? addressController.text.trim()
          : _profileAddress,
    );
    await _loadProfile();
  }

  Future<void> _logout() async {
    await _authService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _showNotifications() async {
    const notifications = [
      'Corrida aceita: Aisha P. • 5 min',
      'Pagamento confirmado: 2.500 CFA',
      'Sua viagem foi concluída com sucesso.',
    ];

    if (!mounted) return;
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

  Future<void> _showRideStatusDialog() async {
    final currentRide = _rideLifeCycle.currentRide;
    if (currentRide == null) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Viagem em curso'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estado: $_rideStatusMessage'),
            const SizedBox(height: 8),
            Text('Origem: ${currentRide['from'] ?? 'Local de partida'}'),
            const SizedBox(height: 4),
            Text(
                'Destino: ${currentRide['to'] ?? (_destinationController.text.trim().isEmpty ? 'Destino' : _destinationController.text.trim())}'),
            const SizedBox(height: 4),
            Text('Valor: ${currentRide['fare'] ?? '$_estimatedFare CFA'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Fechar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar viagem'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      _rideLifeCycle.clear();
      setState(() => _rideAccepted = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viagem cancelada com sucesso.')),
      );
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _requestCurrentLocation() async {
    setState(() => _locationLoading = true);

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Permita a localização para localizar melhor a sua viagem.')),
          );
          setState(() => _locationLoading = false);
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final nextLocation = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _currentLocation = nextLocation;
        _locationLoading = false;
      });

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: nextLocation, zoom: 13),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível obter a sua localização.')),
      );
    }
  }

  Future<void> _requestRide() async {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o destino da sua viagem.')),
      );
      return;
    }

    setState(() => _loading = true);
    final ride = await _api.requestRide(
      destination: destination,
      category: _category,
      paymentMethod: _payment,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideTrackingScreen(ride: ride),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                _buildHeader(),
                const SizedBox(height: 18),
                if (_rideAccepted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F8F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _rideLifeCycle.currentStage == RideStage.arrived
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: const Color(0xFF0B8F62),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _rideStatusMessage,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _showRideStatusDialog,
                          child: const Text('Detalhes'),
                        ),
                      ],
                    ),
                  ),
                _buildMap(),
                const SizedBox(height: 18),
                _buildRouteSummary(),
                const SizedBox(height: 18),
                _buildTripForm(),
              ],
            ),
            _buildTripsTab(),
            _buildProfileTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Viagens',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildTripsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const Text(
          'Minhas viagens',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        ..._tripHistory.map((trip) => _TripHistoryCard(trip: trip)),
      ],
    );
  }

  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const Text(
          'Perfil',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFFDDF5EA),
                  child: Icon(Icons.person, color: Color(0xFF0B8F62), size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_profileName,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(_profileEmail,
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _editProfile,
                  icon:
                      const Icon(Icons.edit_outlined, color: Color(0xFF0B8F62)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Row(
          children: [
            Expanded(
                child: _StatCard(
                    label: 'Viagens',
                    value: '18',
                    icon: Icons.local_taxi_rounded)),
            SizedBox(width: 12),
            Expanded(
                child: _StatCard(
                    label: 'Gasto',
                    value: '12k CFA',
                    icon: Icons.account_balance_wallet_rounded)),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded,
                        color: Color(0xFF0B8F62)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Carteira NhaCarro',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Saldo disponível',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_walletBalance CFA',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _topUpWallet,
                        child: const Text('Carregar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selectedTab = 1),
                        child: const Text('Histórico'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Últimas movimentações',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ..._walletTransactions.take(3).map((entry) {
                  final amount = entry['amount'] as int;
                  final isCredit = amount >= 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isCredit
                                ? const Color(0xFFE0F5EA)
                                : const Color(0xFFFFF1E8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCredit
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            size: 16,
                            color: isCredit
                                ? const Color(0xFF0B8F62)
                                : const Color(0xFFE39A1E),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry['label'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(entry['date'] as String,
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(
                          '${isCredit ? '+' : '-'}${amount.abs()} CFA',
                          style: TextStyle(
                            color: isCredit
                                ? const Color(0xFF0B8F62)
                                : Colors.black87,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Column(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.phone_rounded, color: Color(0xFF0B8F62)),
                title: Text(_profilePhone),
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined,
                    color: Color(0xFF0B8F62)),
                title: Text(_profileAddress),
              ),
              ListTile(
                leading:
                    const Icon(Icons.payment_rounded, color: Color(0xFF0B8F62)),
                title: const Text('Pagamento preferido'),
                subtitle: Text(_payment == PaymentMethod.cash
                    ? 'Dinheiro'
                    : _payment == PaymentMethod.orangeMoney
                        ? 'Orange Money'
                        : 'MTN Mobile Money'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final selection = await showDialog<PaymentMethod>(
                    context: context,
                    builder: (context) => SimpleDialog(
                      title: const Text('Escolha o método preferido'),
                      children: PaymentMethod.values.map((method) {
                        final label = method == PaymentMethod.cash
                            ? 'Dinheiro'
                            : method == PaymentMethod.orangeMoney
                                ? 'Orange Money'
                                : 'MTN Mobile Money';
                        return SimpleDialogOption(
                          onPressed: () => Navigator.of(context).pop(method),
                          child: Text(label),
                        );
                      }).toList(),
                    ),
                  );

                  if (selection != null) {
                    await _updatePreferredPayment(selection);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_rounded,
                    color: Color(0xFF0B8F62)),
                title: const Text('Central de ajuda'),
                subtitle: const Text('Suporte, segurança e ajuda rápida'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SupportScreen()),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sair da conta'),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFDDF5EA),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.local_taxi, color: Color(0xFF0B8F62)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Olá, passageiro!',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              Text(
                'Para onde vamos?',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _showNotifications,
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }

  Widget _buildMap() {
    const googleMapsApiKey = String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: '',
    );

    if (googleMapsApiKey.isEmpty) {
      return Container(
        height: 220,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE7F8F0), Color(0xFFE4EEE9)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _MapPainter()),
            ),
            Positioned(
              left: 24,
              top: 24,
              child: _mapChip(Icons.map_outlined, 'Bissau'),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: FloatingActionButton.small(
                heroTag: 'locationFallback',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0B8F62),
                onPressed: _requestCurrentLocation,
                child: _locationLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(220),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Mapa pronto para Google Maps API',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 220,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentLocation,
            zoom: 12.5,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (controller) {
            _mapController = controller;
            if (_currentLocation != _bissauLocation) {
              controller.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: _currentLocation, zoom: 13),
                ),
              );
            }
          },
          markers: {
            Marker(
              markerId: const MarkerId('pickup'),
              position: _currentLocation,
              infoWindow: const InfoWindow(title: 'Sua localização'),
            ),
          },
        ),
      ),
    );
  }

  Widget _mapChip(IconData icon, String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF0B8F62)),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteSummary() {
    final paymentLabel = _payment == PaymentMethod.cash
        ? 'Dinheiro'
        : _payment == PaymentMethod.orangeMoney
            ? 'Orange Money'
            : 'MTN Mobile Money';
    final categoryLabel = switch (_category) {
      RideCategory.taxi => 'Taxi',
      RideCategory.confort => 'Confort',
      RideCategory.moto => 'Moto',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route_rounded, color: Color(0xFF0B8F62)),
              SizedBox(width: 8),
              Text('Resumo da viagem',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'Destino',
            value: _destinationController.text.trim().isEmpty
                ? 'Ainda não definido'
                : _destinationController.text.trim(),
          ),
          _SummaryRow(label: 'Categoria', value: categoryLabel),
          _SummaryRow(label: 'Pagamento', value: paymentLabel),
          _SummaryRow(
              label: 'Estimativa',
              value: '$_estimatedFare CFA • $_estimatedTravelTime'),
        ],
      ),
    );
  }

  Widget _buildTripForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _destinationController,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_destinationController.text.trim().isNotEmpty && !_loading) {
              _requestRide();
            }
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Para onde vamos?',
            suffixIcon: _destinationController.text.trim().isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () async {
                          final destination =
                              _destinationController.text.trim();
                          if (destination.isEmpty) return;
                          await _saveFavoritePlace(destination);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Local salvo: $destination')),
                          );
                        },
                        icon: const Icon(Icons.bookmark_add_outlined),
                        tooltip: 'Guardar local favorito',
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _destinationController.clear()),
                        icon: const Icon(Icons.clear_rounded),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Locais frequentes',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _favoritePlaces.map((place) {
            final isSelected = _destinationController.text.trim() == place;
            return InputChip(
              label: Text(place),
              selected: isSelected,
              selectedColor: const Color(0xFFE0F5EA),
              onPressed: () =>
                  setState(() => _destinationController.text = place),
              onDeleted: () async {
                if (_favoritePlaces.length <= 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Mantém pelo menos um local favorito.')),
                  );
                  return;
                }
                await _removeFavoritePlace(place);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7F1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.attach_money_rounded, color: Color(0xFF0B8F62)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimativa da viagem',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_estimatedFare CFA • $_estimatedTravelTime',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Escolha a categoria',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Row(
          children: RideCategory.values
              .map((category) => Expanded(child: _categoryCard(category)))
              .toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'Forma de pagamento',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<PaymentMethod>(
          initialValue: _payment,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.payments)),
          items: const [
            DropdownMenuItem(
              value: PaymentMethod.cash,
              child: Text('Dinheiro'),
            ),
            DropdownMenuItem(
              value: PaymentMethod.orangeMoney,
              child: Text('Orange Money'),
            ),
            DropdownMenuItem(
              value: PaymentMethod.mtnMoney,
              child: Text('MTN Mobile Money'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _payment = value);
              _authService.savePreferredPayment(value.name);
            }
          },
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF0B8F62)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pagamento em ${_payment == PaymentMethod.cash ? 'dinheiro' : _payment == PaymentMethod.orangeMoney ? 'Orange Money' : 'MTN Mobile Money'} não exige confirmação extra.',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 54,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _requestRide,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(
                _loading ? 'A procurar motorista...' : 'Confirmar NhaCarro'),
          ),
        ),
      ],
    );
  }

  Widget _categoryCard(RideCategory category) {
    final selected = _category == category;
    final details = switch (category) {
      RideCategory.taxi => ('Taxi', Icons.local_taxi, '2.500 CFA'),
      RideCategory.confort => ('Confort', Icons.directions_car, '3.500 CFA'),
      RideCategory.moto => ('Moto', Icons.two_wheeler, '1.800 CFA'),
    };

    return GestureDetector(
      onTap: () => setState(() => _category = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 7),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0F5EA) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? const Color(0xFF0B8F62) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(details.$2, color: const Color(0xFF0B8F62)),
            const SizedBox(height: 5),
            Text(details.$1,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(details.$3, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _TripHistoryCard extends StatelessWidget {
  const _TripHistoryCard({required this.trip});

  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDDF5EA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_taxi_rounded,
                  color: Color(0xFF0B8F62)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip['route'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(trip['date'] as String,
                      style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(trip['fare'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  trip['status'] as String,
                  style: TextStyle(
                    color: trip['status'] == 'Agendada'
                        ? const Color(0xFFE39A1E)
                        : const Color(0xFF0B8F62),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  final String label;
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
            Icon(icon, color: const Color(0xFF0B8F62)),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: Colors.black54)),
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

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke;
    final minorRoad = Paint()
      ..color = const Color(0xFFC8DCD2)
      ..strokeWidth = 2;
    final route = Paint()
      ..color = const Color(0xFF0B8F62)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, size.height * .72),
        Offset(size.width, size.height * .25), road);
    canvas.drawLine(Offset(size.width * .12, 0),
        Offset(size.width * .72, size.height), road);
    canvas.drawLine(Offset(0, size.height * .18),
        Offset(size.width, size.height * .78), road);
    canvas.drawLine(Offset(0, size.height * .72),
        Offset(size.width, size.height * .25), minorRoad);
    canvas.drawLine(Offset(size.width * .12, 0),
        Offset(size.width * .72, size.height), minorRoad);
    canvas.drawLine(
      Offset(size.width * .17, size.height * .82),
      Offset(size.width * .76, size.height * .28),
      route,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
