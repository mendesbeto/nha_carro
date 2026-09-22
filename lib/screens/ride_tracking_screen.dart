import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/ride_request.dart';
import '../services/api_service.dart';

class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({required this.ride, super.key});

  final RideRequest ride;

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  final _api = ApiService();
  Timer? _pollTimer;
  Map<String, dynamic>? _serverRide;
  bool _arrived = false;
  bool _cancelled = false;
  double _rating = 4.5;

  String get _serverStatus => _serverRide?['status']?.toString() ?? 'SOLICITADA';

  Map<String, dynamic>? get _driver =>
      _serverRide?['motorista'] is Map
          ? Map<String, dynamic>.from(_serverRide!['motorista'] as Map)
          : null;

  String get _tripStageLabel {
    switch (_serverStatus) {
      case 'ACEITA': return 'Motorista a caminho';
      case 'EM_ANDAMENTO': return 'Viagem em andamento';
      case 'CONCLUIDA': return 'Chegou ao destino';
      case 'CANCELADA': return 'Viagem cancelada';
      default: return 'A procurar motorista';
    }
  }

  String get _tripStageSubtitle {
    switch (_serverStatus) {
      case 'ACEITA': return 'O motorista aceitou a viagem e está a caminho.';
      case 'EM_ANDAMENTO': return 'A sua viagem está em andamento.';
      case 'CONCLUIDA': return 'A viagem foi concluída pelo motorista.';
      case 'CANCELADA': return 'A viagem foi cancelada.';
      default: return 'A aguardar um motorista aceitar a solicitação.';
    }
  }

  @override
  void initState() {
    super.initState();
    _pollRideStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollRideStatus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollRideStatus() async {
    final rideId = widget.ride.rideId;
    if (rideId == null || rideId.isEmpty) return;
    try {
      final ride = await _api.getRide(rideId);
      if (!mounted) return;
      setState(() {
        _serverRide = ride;
        _arrived = ride['status']?.toString() == 'CONCLUIDA';
      });
      final status = ride['status']?.toString();
      if (status == 'CONCLUIDA' || status == 'CANCELADA') {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // Keep the last server state visible while connectivity is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    const googleMapsApiKey = String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: '',
    );

    final mapWidget = googleMapsApiKey.isEmpty
        ? Positioned.fill(
            child: CustomPaint(painter: _TrackingMapPainter(0.0)),
          )
        : Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(11.8811, -15.6177),
                zoom: 12,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              markers: {
                if (_driver != null)
                  const Marker(
                    markerId: MarkerId('driver'),
                    position: LatLng(11.8811, -15.6177),
                    infoWindow: InfoWindow(title: 'Motorista'),
                  ),
                Marker(
                  markerId: const MarkerId('destination'),
                  position: const LatLng(11.8811, -15.6177),
                  infoWindow: InfoWindow(title: widget.ride.destination),
                ),
              },
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acompanhar corrida'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          mapWidget,
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: _buildDriverCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard() {
    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _arrived
                  ? 'O motorista chegou!'
                  : _tripStageLabel,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _tripStageSubtitle,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 15),
            if (_driver == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: Color(0xFF0B8F62)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nenhum motorista aceitou ainda. Aguardando disponibilidade...',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Color(0xFFDDF5EA),
                    child: Icon(Icons.person, color: Color(0xFF0B8F62)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _driver!['nome']?.toString() ?? 'Motorista',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          (_driver!['veiculo'] is Map)
                              ? '${(_driver!['veiculo'] as Map)['modelo'] ?? 'Veículo'} · ${(_driver!['veiculo'] as Map)['placa'] ?? 'Matrícula'}'
                              : 'Veículo não informado',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        Text(
                          '★ ${(_driver!['avaliacaoMedia'] as num?)?.toStringAsFixed(1) ?? '—'}',
                          style: const TextStyle(color: Color(0xFFE39A1E)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.phone_outlined)),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.chat_bubble_outline)),
                ],
              ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Color(0xFF0B8F62)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.ride.destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${widget.ride.estimatedFare} CFA',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (_cancelled) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Voltar ao início'),
                ),
              ),
            ] else if (!_arrived) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Cancelar viagem?'),
                            content: const Text(
                              'A viagem será cancelada e o reembolso será processado em até 24 horas.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Manter'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Cancelar'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true && mounted) {
                          final rideId = widget.ride.rideId;
                          if (rideId == null || rideId.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Não foi possível identificar a corrida para cancelamento.'),
                              ),
                            );
                            return;
                          }

                          try {
                            await _api.cancelRide(rideId);
                            if (!mounted) return;
                            setState(() {
                              _cancelled = true;
                              _serverRide = {...?_serverRide, 'status': 'CANCELADA'};
                            });
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Viagem cancelada.')),
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
                          }
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
              const Text(
                'Avalie a sua viagem',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(5, (index) {
                  final starValue = index + 1;
                  final filled = _rating >= starValue;
                  return IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _rating = starValue.toDouble()),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: const Color(0xFFE39A1E),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Avaliação enviada: $_rating/5'),
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Concluir viagem'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackingMapPainter extends CustomPainter {
  _TrackingMapPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFE4EEE9), BlendMode.src);
    final road = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..strokeWidth = 25
      ..style = PaintingStyle.stroke;
    final route = Paint()
      ..color = const Color(0xFF0B8F62)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    final start = Offset(size.width * .2, size.height * .68);
    final end = Offset(size.width * .78, size.height * .25);
    canvas.drawLine(start, end, road);
    canvas.drawLine(start, end, route);
    final driver = Offset(
      start.dx + (end.dx - start.dx) * progress,
      start.dy + (end.dy - start.dy) * progress,
    );
    canvas.drawCircle(driver, 19, Paint()..color = const Color(0xFF0B8F62));
    canvas.drawCircle(driver, 9, Paint()..color = Colors.white);
    canvas.drawCircle(end, 13, Paint()..color = const Color(0xFFE39A1E));
  }

  @override
  bool shouldRepaint(covariant _TrackingMapPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
