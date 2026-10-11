import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/api_service.dart';

class DriverRideMapScreen extends StatefulWidget {
  const DriverRideMapScreen({required this.ride, super.key});

  final Map<String, dynamic> ride;

  @override
  State<DriverRideMapScreen> createState() => _DriverRideMapScreenState();
}

class _DriverRideMapScreenState extends State<DriverRideMapScreen> {
  static const LatLng _bissau = LatLng(11.8811, -15.6177);

  final ApiService _api = ApiService();
  final Set<Marker> _markers = {};
  Timer? _refreshTimer;
  GoogleMapController? _mapController;
  Map<String, dynamic>? _ride;
  LatLng? _lastDriverLocation;
  bool _loading = true;
  String? _error;

  String get _rideId => widget.ride['rideId']?.toString() ?? '';

  String get _status => _ride?['status']?.toString() ?? 'ACEITA';

  LatLng? _point(dynamic raw) {
    if (raw is! Map) return null;
    final coordinates = raw['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;
    final longitude = num.tryParse(coordinates[0].toString());
    final latitude = num.tryParse(coordinates[1].toString());
    if (latitude == null || longitude == null) return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return null;
    }
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  LatLng? get _origin => _point(_ride?['origem'] ?? _ride?['origem_coords']);

  LatLng? get _destination =>
      _point(_ride?['destino'] ?? _ride?['destino_coords']);

  LatLng? get _driverLocation {
    final driver = _ride?['motorista'];
    if (driver is! Map) return null;
    final location = driver['localizacao'];
    if (location is! Map) return null;
    final latitude = num.tryParse(location['latitude']?.toString() ?? '');
    final longitude = num.tryParse(location['longitude']?.toString() ?? '');
    if (latitude == null || longitude == null) return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return null;
    }
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  LatLng get _mapCenter =>
      _driverLocation ?? _origin ?? _destination ?? _bissau;

  String get _targetLabel =>
      _status == 'EM_ANDAMENTO' ? 'Destino da viagem' : 'Ponto de recolha';

  @override
  void initState() {
    super.initState();
    _ride = Map<String, dynamic>.from(widget.ride);
    _refreshRide();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshRide(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _refreshRide() async {
    if (_rideId.isEmpty) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Não foi possível identificar esta corrida.';
      });
      return;
    }

    try {
      final latest = await _api.getRide(_rideId);
      if (!mounted) return;
      final previousDriver = _lastDriverLocation;
      setState(() {
        _ride = latest;
        _loading = false;
        _error = null;
        _rebuildMarkers();
      });
      final currentDriver = _driverLocation;
      if (currentDriver != null &&
          currentDriver != previousDriver &&
          _mapController != null) {
        _lastDriverLocation = currentDriver;
        await _mapController!.animateCamera(
          CameraUpdate.newLatLng(currentDriver),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _rebuildMarkers() {
    _markers
      ..clear()
      ..addAll([
        if (_origin != null)
          Marker(
            markerId: const MarkerId('pickup'),
            position: _origin!,
            infoWindow: const InfoWindow(title: 'Ponto de recolha'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
          ),
        if (_destination != null)
          Marker(
            markerId: const MarkerId('destination'),
            position: _destination!,
            infoWindow: const InfoWindow(title: 'Destino'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
          ),
        if (_driverLocation != null)
          Marker(
            markerId: const MarkerId('driver'),
            position: _driverLocation!,
            infoWindow: const InfoWindow(title: 'Localização do motorista'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          ),
      ]);
  }

  Future<void> _centerOnDriver() async {
    final location = _driverLocation;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A localização atual do motorista ainda não está disponível.'),
        ),
      );
      return;
    }
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(location, 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    const googleMapsApiKey = String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: '',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa da corrida'),
        actions: [
          IconButton(
            tooltip: 'Atualizar mapa',
            onPressed: _refreshRide,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: googleMapsApiKey.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'O mapa não está configurado nesta compilação. Verifique GOOGLE_MAPS_API_KEY.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _mapCenter,
                      zoom: 14,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _rebuildMarkers();
                    },
                    markers: _markers,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    compassEnabled: true,
                    mapToolbarEnabled: false,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 16,
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _status == 'EM_ANDAMENTO'
                                ? 'Viagem em andamento'
                                : 'A caminho do passageiro',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('A acompanhar a localização a cada 5 segundos.'),
                          const SizedBox(height: 8),
                          Text(
                            'Marcadores: motorista, recolha e destino. A linha de navegação pelas estradas depende da ativação do serviço Google Directions.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: FloatingActionButton(
                    onPressed: _centerOnDriver,
                    tooltip: 'Centrar no motorista',
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
    );
  }
}
