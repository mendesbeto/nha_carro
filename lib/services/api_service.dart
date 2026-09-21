import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ride_request.dart';
import 'auth_service.dart';

class ApiService {
  static const String _baseUrl = 'https://nha-carro.onrender.com/api';

  Future<Map<String, String>> _headers({bool authenticated = false}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (authenticated) {
      final token = await AuthService().getAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('Sessão expirada. Faça login novamente.');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String password,
    required String telefone,
    required String role,
    String? vehicle,
    String? plate,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'email': email,
        'telefone': telefone,
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

  Future<Map<String, dynamic>> refreshSession() async {
    final auth = AuthService();
    final refreshToken = await auth.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('Sessão expirada. Faça login novamente.');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/refresh'),
      headers: await _headers(),
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      await auth.clearSession();
      throw Exception(
        data['message'] ??
            data['error'] ??
            'Sessão expirada. Faça login novamente.',
      );
    }

    final accessToken = data['access_token'] as String?;
    final newRefreshToken = data['refresh_token'] as String?;
    if (accessToken == null || newRefreshToken == null) {
      await auth.clearSession();
      throw Exception('Resposta de sessão inválida.');
    }

    await auth.updateTokens(
      accessToken: accessToken,
      refreshToken: newRefreshToken,
    );
    return data;
  }

  Future<void> logout() async {
    final auth = AuthService();
    final refreshToken = await auth.getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/auth/logout'),
          headers: await _headers(),
          body: jsonEncode({'refreshToken': refreshToken}),
        );
      } finally {
        await auth.clearSession();
      }
    } else {
      await auth.clearSession();
    }
  }

  Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function() request, {
    bool retry = true,
  }) async {
    final response = await request();
    if (response.statusCode != 401 || !retry) return response;

    try {
      await refreshSession();
      return await request();
    } catch (_) {
      return response;
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: await _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Credenciais inválidas.');
    }
    return data;
  }

  Future<void> requestPasswordReset({required String email}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/request-password-reset'),
      headers: await _headers(),
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode >= 400) {
      final data = _decodeBody(response);
      throw Exception(
        data['message'] ?? data['error'] ?? 'Não foi possível solicitar a recuperação.',
      );
    }
  }

  Future<void> resetPassword({
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/reset-password'),
      headers: await _headers(),
      body: jsonEncode({
        'token': token,
        'password': password,
        'passwordConfirmation': passwordConfirmation,
      }),
    );
    if (response.statusCode >= 400) {
      final data = _decodeBody(response);
      throw Exception(
        data['message'] ?? data['error'] ?? 'Não foi possível alterar a palavra-passe.',
      );
    }
  }

  Future<Map<String, dynamic>> getWallet() async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse('$_baseUrl/wallet'),
        headers: await _headers(authenticated: true),
      ),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Não foi possível carregar a carteira.');
    }
    return data;
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: await _headers(authenticated: true),
      ),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Sessão inválida.');
    }
    return data;
  }

  Future<Map<String, dynamic>> setDriverAvailability({
    required bool online,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _authenticatedRequest(
      () async => http.patch(
        Uri.parse('$_baseUrl/rides/availability'),
        headers: await _headers(authenticated: true),
        body: jsonEncode({
          'online': online,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        }),
      ),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(
        data['error'] ?? 'Não foi possível atualizar a disponibilidade.',
      );
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> getAvailableRides() async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse('$_baseUrl/rides/available'),
        headers: await _headers(authenticated: true),
      ),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Não foi possível carregar as corridas disponíveis.');
    }

    final rides = data['rides'];
    if (rides is! List) return <Map<String, dynamic>>[];
    return rides.whereType<Map>().map((ride) => Map<String, dynamic>.from(ride)).toList();
  }

  Future<Map<String, dynamic>> getRide(String rideId) async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse('$_baseUrl/rides/$rideId'),
        headers: await _headers(authenticated: true),
      ),
    );
    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Não foi possível carregar a corrida.');
    }
    return data;
  }

  Future<Map<String, dynamic>> acceptRide(String rideId) =>
      _rideAction('/rides/$rideId/accept');

  Future<Map<String, dynamic>> startRide(String rideId) =>
      _rideAction('/rides/$rideId/start');

  Future<Map<String, dynamic>> completeRide(String rideId) =>
      _rideAction('/rides/$rideId/complete');

  Future<Map<String, dynamic>> cancelRide(String rideId) =>
      _rideAction('/rides/$rideId/cancel');

  Future<Map<String, dynamic>> _rideAction(String path) async {
    final response = await _authenticatedRequest(
      () async => http.patch(
        Uri.parse('$_baseUrl$path'),
        headers: await _headers(authenticated: true),
      ),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Não foi possível atualizar a corrida.');
    }
    return data;
  }

  Future<RideRequest> requestRide({
    required String destination,
    required RideCategory category,
    required PaymentMethod paymentMethod,
    required double originLat,
    required double originLng,
    double? destinationLat,
    double? destinationLng,
  }) async {
    final response = await _authenticatedRequest(
      () async => http.post(
        Uri.parse('$_baseUrl/rides/request'),
        headers: await _headers(authenticated: true),
        body: jsonEncode({
          'destination': destination,
          'category': category.name,
          'paymentMethod': paymentMethod.name,
          'originLat': originLat,
          'originLng': originLng,
          if (destinationLat != null) 'destinationLat': destinationLat,
          if (destinationLng != null) 'destinationLng': destinationLng,
        }),
      ),
    );

    final data = _decodeBody(response);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Erro ao solicitar corrida.');
    }

    return RideRequest(
      origin: data['origin'] as String? ?? 'A minha localização',
      destination: data['destination'] as String? ?? destination,
      category: RideCategory.values.firstWhere(
        (value) =>
            value.name == (data['category'] as String? ?? category.name),
        orElse: () => category,
      ),
      paymentMethod: PaymentMethod.values.firstWhere(
        (value) => value.name == (data['paymentMethod'] as String? ?? paymentMethod.name),
        orElse: () => paymentMethod,
      ),
      estimatedFare: data['estimatedFare'] as int? ?? _fareFor(category),
      rideId: data['rideId'] as String?,
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
