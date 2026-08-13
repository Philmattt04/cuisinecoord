import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_data.dart';

class UserStorage {
  UserStorage._();
  static final UserStorage instance = UserStorage._();

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  // ── Hidden restaurants ────────────────────────────────────────────────────

  Future<List<String>> loadHiddenIds() async =>
      (await _p).getStringList('cc_hidden') ?? [];

  Future<void> saveHiddenIds(List<String> ids) async =>
      (await _p).setStringList('cc_hidden', ids);

  // ── Dining history ────────────────────────────────────────────────────────

  Future<List<DiningVisit>> loadDiningHistory() async {
    final raw = (await _p).getStringList('cc_history') ?? [];
    return raw
        .map((s) => DiningVisit.fromJson(jsonDecode(s)))
        .toList();
  }

  Future<void> saveDiningHistory(List<DiningVisit> history) async =>
      (await _p).setStringList(
          'cc_history', history.map((v) => jsonEncode(v.toJson())).toList());

  // ── Collections ───────────────────────────────────────────────────────────

  Future<List<RestaurantCollection>> loadCollections() async {
    final raw = (await _p).getStringList('cc_collections') ?? [];
    return raw
        .map((s) => RestaurantCollection.fromJson(jsonDecode(s)))
        .toList();
  }

  Future<void> saveCollections(List<RestaurantCollection> cols) async =>
      (await _p).setStringList(
          'cc_collections', cols.map((c) => jsonEncode(c.toJson())).toList());
}
