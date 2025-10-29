import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/feed_source.dart';

class SubscriptionManager {
  static const _key = 'subscriptions';

  Future<List<FeedSource>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final arr = jsonDecode(raw) as List<dynamic>;
    return arr.map((e) => FeedSource.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> save(List<FeedSource> list) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(list.map((e) => e.toMap()).toList());
    await prefs.setString(_key, encoded);
  }
}
