import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _roleKey = 'nhacarro_user_role';
  static const String _nameKey = 'nhacarro_user_name';
  static const String _emailKey = 'nhacarro_user_email';
  static const String _phoneKey = 'nhacarro_user_phone';
  static const String _addressKey = 'nhacarro_user_address';
  static const String _rememberMeKey = 'nhacarro_remember_me';
  static const String _preferredPaymentKey = 'nhacarro_preferred_payment';
  static const String _driverOnlineKey = 'nhacarro_driver_online';
  static const String _favoritePlacesKey = 'nhacarro_favorite_places';

  Future<void> saveSession({
    required String role,
    required String name,
    required String email,
    String? phone,
    String? address,
    bool rememberMe = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, rememberMe);
    if (!rememberMe) {
      await clearSession();
      return;
    }
    await prefs.setString(_roleKey, role);
    await prefs.setString(_nameKey, name);
    await prefs.setString(_emailKey, email);
    if (phone != null) {
      await prefs.setString(_phoneKey, phone);
    }
    if (address != null) {
      await prefs.setString(_addressKey, address);
    }
  }

  Future<void> savePreferredPayment(String paymentMethod) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredPaymentKey, paymentMethod);
  }

  Future<String> loadPreferredPayment() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_preferredPaymentKey) ?? 'orangeMoney';
  }

  Future<void> saveDriverAvailability(bool online) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_driverOnlineKey, online);
  }

  Future<bool> loadDriverAvailability() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_driverOnlineKey) ?? false;
  }

  Future<Map<String, String?>> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_rememberMeKey) ?? true;
    if (!rememberMe) {
      await clearSession();
      return {
        'role': null,
        'name': null,
        'email': null,
        'phone': null,
        'address': null,
      };
    }
    return {
      'role': prefs.getString(_roleKey),
      'name': prefs.getString(_nameKey),
      'email': prefs.getString(_emailKey),
      'phone': prefs.getString(_phoneKey),
      'address': prefs.getString(_addressKey),
    };
  }

  Future<void> saveFavoritePlaces(List<String> places) async {
    final prefs = await SharedPreferences.getInstance();
    final uniquePlaces = places
        .map((place) => place.trim())
        .where((place) => place.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_favoritePlacesKey, uniquePlaces);
  }

  Future<List<String>> loadFavoritePlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final places = prefs.getStringList(_favoritePlacesKey) ?? const [];
    return places
        .map((place) => place.trim())
        .where((place) => place.isNotEmpty)
        .toList();
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_addressKey);
    await prefs.remove(_rememberMeKey);
    await prefs.remove(_preferredPaymentKey);
    await prefs.remove(_driverOnlineKey);
    await prefs.remove(_favoritePlacesKey);
  }
}
