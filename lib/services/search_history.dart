import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistory {
  static const _prefsKey = 'search_recent_v1';
  static const _maxItems = 20;

  Future<List<String>> getRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<String> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(items));
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final list = await getRecent();
    // Move to front, ensure uniqueness
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    // Cap size
    if (list.length > _maxItems) {
      list.removeRange(_maxItems, list.length);
    }
    await _save(list);
  }

  Future<void> remove(String query) async {
    final list = await getRecent();
    list.removeWhere((e) => e.toLowerCase() == query.trim().toLowerCase());
    await _save(list);
  }

  Future<void> clear() async {
    await _save([]);
  }
}
