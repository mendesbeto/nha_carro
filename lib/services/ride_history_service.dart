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
    await chargeWallet(_toCfaValue(fare), description: 'Pagamento da viagem: $route');
  }

  Future<int> loadWalletBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_walletKey) ?? 5000;
  }

  Future<void> updateWalletBalance(int amountCfa) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadWalletBalance();
    final next = current + amountCfa;
    await prefs.setInt(_walletKey, next < 0 ? 0 : next);
  }

  Future<void> chargeWallet(int amountCfa, {required String description}) async {
    if (amountCfa <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await loadWalletBalance();
    final next = current - amountCfa;
    await prefs.setInt(_walletKey, next < 0 ? 0 : next);
    await _addTransaction(
      label: description,
      amountCfa: -amountCfa,
      type: 'debit',
    );
  }

  Future<void> addWalletCredit(int amountCfa) async {
    if (amountCfa <= 0) return;
    await updateWalletBalance(amountCfa);
    await _addTransaction(
      label: 'Carregamento de carteira',
      amountCfa: amountCfa,
      type: 'credit',
    );
  }

  Future<void> _addTransaction({
    required String label,
    required int amountCfa,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final transactions = await loadTransactions();
    transactions.insert(0, {
      'label': label,
      'amount': amountCfa,
      'type': type,
      'date': 'Hoje • ${_formatTime(DateTime.now())}',
    });
    final payload = transactions
        .map((entry) => jsonEncode(entry))
        .toList(growable: false);
    await prefs.setStringList(_transactionsKey, payload);
  }

  int _toCfaValue(String fare) {
    final digits = fare.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
