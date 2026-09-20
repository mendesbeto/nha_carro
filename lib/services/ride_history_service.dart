import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RideHistoryService {
  static const String _historyKey = 'nhacarro_trip_history';
  static const String _walletKey = 'nhacarro_wallet_balance';
  static const String _transactionsKey = 'nhacarro_wallet_transactions';

  Future<List<Map<String, dynamic>>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries = prefs.getStringList(_historyKey) ?? const <String>[];

    return rawEntries.map((entry) {
      try {
        return jsonDecode(entry) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((entry) => entry.isNotEmpty).toList();
  }

  Future<List<Map<String, dynamic>>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries = prefs.getStringList(_transactionsKey) ?? const <String>[];

    return rawEntries.map((entry) {
      try {
        return jsonDecode(entry) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((entry) => entry.isNotEmpty).toList();
  }

  Future<void> addCompletedRide({
    required String route,
    required String fare,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory();
    final nextEntry = {
      'route': route,
      'date': 'Hoje • ${_formatTime(DateTime.now())}',
      'status': 'Concluída',
      'fare': fare,
    };

    history.insert(0, nextEntry);
    final payload = history
        .map((entry) => jsonEncode(entry))
        .toList(growable: false);

    await prefs.setStringList(_historyKey, payload);
  }

  Future<int> loadWalletBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_walletKey) ?? 5000;
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
