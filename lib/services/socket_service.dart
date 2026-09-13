import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

class DriverLocation {
  const DriverLocation({
    required this.progress,
    required this.minutesAway,
  });

  final double progress;
  final int minutesAway;
}

class SocketService {
  final StreamController<DriverLocation> _driverLocationController =
      StreamController<DriverLocation>.broadcast();
  socket_io.Socket? _socket;
  Timer? _fallbackTimer;
  DriverLocation _lastLocation = const DriverLocation(progress: 0, minutesAway: 6);

  Stream<DriverLocation> trackDriver() {
    _ensureFallbackSimulation();
    return _driverLocationController.stream;
  }

  void initSocket(String userId) {
    if (_socket != null) return;

    final socket = socket_io.io(
      'http://api.nhacarro.com',
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      },
    );
    _socket = socket;

    socket.onConnect((_) {
      debugPrint('Conectado ao servidor NhaCarro');
      socket.emit('join_room', userId);
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
    });
    socket.onDisconnect((_) {
      debugPrint('Desconectado do servidor NhaCarro');
      _ensureFallbackSimulation();
    });
    socket.onConnectError((error) {
      debugPrint('Erro ao conectar ao NhaCarro: $error');
      _ensureFallbackSimulation();
    });
    socket.on('atualizacao_localizacao', _onDriverLocation);
    socket.connect();
  }

  void enviarLocalizacao(String motoristaId, double lat, double lng) {
    final socket = _requireSocket();
    socket.emit('atualizar_localizacao', <String, dynamic>{
      'motoristaId': motoristaId,
      'lat': lat,
      'lng': lng,
    });
  }

  void dispose() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _socket?.off('atualizacao_localizacao', _onDriverLocation);
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _driverLocationController.close();
  }

  socket_io.Socket _requireSocket() {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Inicialize o SocketService antes de emitir eventos.');
    }
    return socket;
  }

  void _ensureFallbackSimulation() {
    if (_fallbackTimer != null || _driverLocationController.isClosed) return;

    _fallbackTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final nextProgress = (_lastLocation.progress + 0.12).clamp(0.0, 1.0);
      _lastLocation = DriverLocation(
        progress: nextProgress,
        minutesAway: nextProgress >= 1 ? 0 : (6 - (nextProgress * 5)).round(),
      );
      _driverLocationController.add(_lastLocation);

      if (nextProgress >= 1) {
        timer.cancel();
        _fallbackTimer = null;
      }
    });
  }

  void _onDriverLocation(dynamic payload) {
    if (payload is! Map) return;

    final progress = _asDouble(payload['progress']);
    final minutesAway = _asInt(payload['minutesAway']);
    if (progress == null || minutesAway == null) return;

    _lastLocation = DriverLocation(
      progress: progress.clamp(0, 1),
      minutesAway: minutesAway < 0 ? 0 : minutesAway,
    );
    _driverLocationController.add(_lastLocation);
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _asInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }
}
