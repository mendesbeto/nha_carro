enum RideCategory {
  taxi,
  confort,
  moto,
}

enum PaymentMethod {
  cash,
  orangeMoney,
  mtnMoney,
}

class RideRequest {
  const RideRequest({
    required this.origin,
    required this.destination,
    required this.category,
    required this.paymentMethod,
    required this.estimatedFare,
  });

  final String origin;
  final String destination;
  final RideCategory category;
  final PaymentMethod paymentMethod;
  final int estimatedFare;

  String get categoryLabel {
    switch (category) {
      case RideCategory.taxi:
        return 'NhaCarro Taxi';
      case RideCategory.confort:
        return 'NhaCarro Confort';
      case RideCategory.moto:
        return 'NhaCarro Moto';
    }
  }

  String get paymentLabel {
    switch (paymentMethod) {
      case PaymentMethod.cash:
        return 'Dinheiro';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
      case PaymentMethod.mtnMoney:
        return 'MTN Mobile Money';
    }
  }
}
