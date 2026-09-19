import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/ride_request.dart';
import '../services/api_service.dart';
import '../services/ride_lifecycle_service.dart';
import '../services/socket_service.dart';

class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({required this.ride, super.key});

  final RideRequest ride;

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  final _socket = SocketService();
  final _api = ApiService();
  StreamSubscription<DriverLocation>? _subscription;
  DriverLocation _location = const DriverLocation(progress: 0, minutesAway: 6);
  bool _arrived = false;
  bool _cancelled = false;
  double _rating = 4.5;

  String get _tripStageLabel {
    final stage = RideLifecycleService.instance.currentRide?['stage'] as String?;
    if (_cancelled || stage == RideStage.cancelled.name) return 'Viagem cancelada';
    if (_arrived || stage == RideStage.arrived.name) return 'Chegou ao destino';
    if (stage == RideStage.inTransit.name || _location.progress >= 0.75) {
      return 'Próximo do destino';
    }
    if (stage == RideStage.pickup.name || _location.progress >= 0.4) {
      return 'Embarque em andamento';
    }
    return 'Motorista a caminho';
  }

  String get _tripStageSubtitle {
    final stage = RideLifecycleService.instance.currentRide?['stage'] as String?;
    if (_cancelled || stage == RideStage.cancelled.name) {
      return 'A viagem foi cancelada e a devolução foi agendada.';
    }
    if (_arrived || stage == RideStage.arrived.name) {
      return 'O motorista chegou ao ponto de destino.';
    }
    if (stage == RideStage.inTransit.name || _location.progress >= 0.75) {
      return 'O motorista está chegando ao ponto de encontro.';
    }
    if (stage == RideStage.pickup.name || _location.progress >= 0.4) {
      return 'O motorista já saiu e segue em direção ao seu local.';
    }
    return 'A sua viagem foi aceita e o motorista está a caminho.';
  }

  @override
  void initState() {
    super.initState();
    _socket.initSocket('ride-${widget.ride.destination.hashCode}');
    _subscription = _socket.trackDriver().listen((location) {
      if (!mounted) return;
      final nextArrived = location.progress >= 1;
      setState(() {
        _location = location;
        _arrived = nextArrived;
      });
      if (nextArrived) {
        RideLifecycleService.instance.updateRideStage(RideStage.arrived);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const googleMapsApiKey = String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: '',
    );

    final mapWidget = googleMapsApiKey.isEmpty
        ? Positioned.fill(
            child: CustomPaint(painter: _TrackingMapPainter(_location.progress)),
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
                  : '$_tripStageLabel · ${_location.minutesAway} min',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _tripStageSubtitle,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0xFFDDF5EA),
                  child: Icon(Icons.person, color: Color(0xFF0B8F62)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mamadou S.', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('Toyota Corolla · AZ-24-GB', style: TextStyle(color: Colors.black54)),
                      Text('★ 4.9', style: TextStyle(color: Color(0xFFE39A1E))),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.phone_outlined),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
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
                child: LinearProgressIndicator(
                  value: _location.progress,
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
                            setState(() => _cancelled = true);
                            RideLifecycleService.instance.updateRideStage(RideStage.cancelled);
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
