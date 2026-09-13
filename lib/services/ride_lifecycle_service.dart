import 'dart:async';

enum RideStage {
  requested,
  accepted,
  pickup,
  inTransit,
  arrived,
  cancelled,
}

class RideLifecycleService {
  RideLifecycleService._();

  static final RideLifecycleService instance = RideLifecycleService._();

  final StreamController<Map<String, dynamic>?> _acceptedRideController =
      StreamController<Map<String, dynamic>?>.broadcast();

  Map<String, dynamic>? _currentRide;
  RideStage _currentStage = RideStage.requested;

  Map<String, dynamic>? get currentRide => _currentRide;
  RideStage get currentStage => _currentStage;

  Stream<Map<String, dynamic>?> get acceptedRideStream =>
      _acceptedRideController.stream;

  void acceptRide(Map<String, dynamic> ride) {
    _currentRide = {...ride, 'stage': RideStage.accepted.name};
    _currentStage = RideStage.accepted;
    _acceptedRideController.add(_currentRide);
  }

  void updateRideStage(RideStage stage) {
    final currentRide = _currentRide;
    if (currentRide == null) return;

    _currentStage = stage;
    _currentRide = {...currentRide, 'stage': stage.name};
    _acceptedRideController.add(_currentRide);
  }

  void clear() {
    _currentRide = null;
    _currentStage = RideStage.requested;
    _acceptedRideController.add(null);
  }

  void dispose() {
    _acceptedRideController.close();
  }
}
