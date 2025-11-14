import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks listening time per artist with monthly periods.
/// Used to identify artists worth supporting based on listening habits.
class ListeningTracker {
  static const _key = 'listening_time_v1';
  static const _supportThresholdSeconds = 1800; // 30 minutes

  /// Get the current period key (e.g., "2025-11" for November 2025)
  String _currentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Load listening data from storage
  Future<Map<String, Map<String, int>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // Structure: { "2025-11": { "artist-key": seconds } }
      return decoded.map((period, artistMap) {
        final Map<String, int> artists = {};
        if (artistMap is Map) {
          artistMap.forEach((artistKey, seconds) {
            if (seconds is int) {
              artists[artistKey.toString()] = seconds;
            }
          });
        }
        return MapEntry(period, artists);
      });
    } catch (_) {
      return {};
    }
  }

  /// Save listening data to storage
  Future<void> _save(Map<String, Map<String, int>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  /// Normalize artist name to a consistent key
  String _normalizeArtist(String artist) {
    return artist.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Record listening time for an artist (call periodically during playback)
  Future<void> recordListeningTime(String artist, int seconds) async {
    if (artist.trim().isEmpty || seconds <= 0) return;
    
    final data = await _load();
    final period = _currentPeriod();
    final artistKey = _normalizeArtist(artist);
    
    final periodData = data.putIfAbsent(period, () => {});
    periodData[artistKey] = (periodData[artistKey] ?? 0) + seconds;
    
    await _save(data);
  }

  /// Get total listening time for an artist in the current month (in seconds)
  Future<int> getListeningTime(String artist, {String? period}) async {
    final data = await _load();
    final targetPeriod = period ?? _currentPeriod();
    final artistKey = _normalizeArtist(artist);
    
    final periodData = data[targetPeriod];
    if (periodData == null) return 0;
    
    return periodData[artistKey] ?? 0;
  }

  /// Get all artists that have exceeded the support threshold this month
  /// Returns a map of artist-key -> seconds listened
  Future<Map<String, int>> getArtistsAboveThreshold({String? period}) async {
    final data = await _load();
    final targetPeriod = period ?? _currentPeriod();
    final periodData = data[targetPeriod];
    
    if (periodData == null) return {};
    
    final result = <String, int>{};
    periodData.forEach((artistKey, seconds) {
      if (seconds >= _supportThresholdSeconds) {
        result[artistKey] = seconds;
      }
    });
    
    return result;
  }

  /// Get listening stats for all periods (for debugging/history)
  Future<Map<String, Map<String, int>>> getAllListeningData() async {
    return await _load();
  }

  /// Clean up old period data (keep last 12 months)
  Future<void> cleanupOldData() async {
    final data = await _load();
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - 12, 1);
    
    final keysToRemove = <String>[];
    data.forEach((period, _) {
      try {
        final parts = period.split('-');
        if (parts.length == 2) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final periodDate = DateTime(year, month, 1);
          if (periodDate.isBefore(cutoff)) {
            keysToRemove.add(period);
          }
        }
      } catch (_) {
        keysToRemove.add(period); // Remove malformed keys
      }
    });
    
    for (final key in keysToRemove) {
      data.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      await _save(data);
    }
  }

  /// Format seconds into a human-readable duration string
  static String formatDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds sec';
    } else if (seconds < 3600) {
      final mins = (seconds / 60).floor();
      return '$mins min';
    } else {
      final hours = (seconds / 3600).floor();
      final mins = ((seconds % 3600) / 60).floor();
      if (mins == 0) {
        return '$hours hr';
      }
      return '$hours hr $mins min';
    }
  }
}
