import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ride_request.dart';

class ApiService {
  static const String _baseUrl = 'https://nha-carro.onrender.com/api';

  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? vehicle,
    String? plate,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'vehicle': vehicle,
        'plate': plate,
      }),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Erro ao criar conta.');
    }

    return data;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Credenciais inválidas.');
    }

    return data;
  }

  Future<RideRequest> requestRide({
    required String destination,
    required RideCategory category,
    required PaymentMethod paymentMethod,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/rides/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'destination': destination,
        'category': category.name,
        'paymentMethod': paymentMethod.name,
      }),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Erro ao solicitar corrida.');
    }

    return RideRequest(
      origin: data['origin'] as String? ?? 'A minha localização',
      destination: data['destination'] as String? ?? destination,
      category: RideCategory.values.firstWhere(
        (value) => value.name == (data['category'] as String? ?? category.name),
        orElse: () => category,
      ),
      paymentMethod: PaymentMethod.values.firstWhere(
        (value) => value.name == (data['paymentMethod'] as String? ?? paymentMethod.name),
        orElse: () => paymentMethod,
      ),
      estimatedFare: data['estimatedFare'] as int? ?? _fareFor(category),
    );
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  int _fareFor(RideCategory category) {
    switch (category) {
      case RideCategory.taxi:
        return 2500;
      case RideCategory.confort:
        return 3500;
      case RideCategory.moto:
        return 1800;
    }
  }
}
