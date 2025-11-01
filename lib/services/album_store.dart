
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/album.dart';
import '../models/track.dart';
import 'feed_metadata.dart';
import 'text_normalizer.dart';

class AlbumStore {
  final _metadataService = FeedMetadataService();

  static const _key = 'albums_all';
  static const _migrationKey = 'albums_normalized_v2';

  /// Normalize stored track titles once per-install when we add normalization
  /// logic later. This will scan saved albums, normalize each track title and
  /// persist the updated map. Idempotent via [_migrationKey].
  Future<void> _ensureStoredTitlesNormalized() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(_migrationKey) ?? false;
    if (migrated) return;

    final m = await _loadMap();
    var changed = false;
    for (final feedId in m.keys) {
      final list = m[feedId] ?? [];
      for (var i = 0; i < list.length; i++) {
        final album = list[i];
        final normalizedTracks = <Track>[];
        var albumChanged = false;
        for (final t in album.tracks) {
          final cleaned = cleanTrackTitle(t.title);
          // Remove everything up to and including "number. " pattern
          final finalTitle = cleaned.replaceFirst(RegExp(r'^.+?\d+\.\s*'), '');
          if (finalTitle != t.title) albumChanged = true;
          normalizedTracks.add(Track(
            id: t.id,
            title: finalTitle,
            url: t.url,
            durationSeconds: t.durationSeconds,
          ));
        }
        if (albumChanged) {
          changed = true;
          list[i] = Album(
            id: album.id,
            title: album.title,
            artist: album.artist,
            coverUrl: album.coverUrl,
            tracks: normalizedTracks,
            description: album.description,
            published: album.published,
          );
        }
      }
      m[feedId] = list;
    }

    if (changed) {
      await _saveMap(m);
    }
    await prefs.setBool(_migrationKey, true);
  }

  /// Force clear all cached albums (removes all stored album data)
  Future<void> clearAllAlbumsCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Attempts to update an album's metadata from its feed
  Future<void> refreshAlbumMetadata(Album album) async {
    if (album.tracks.isEmpty) return;

    // Try both the album ID and first track URL for metadata
    var metadata = await _metadataService.findMetadataForAlbum(album.id);

    if (metadata == null) {
      // Fall back to using first track URL if album ID didn't work
      final firstTrackUrl = album.tracks.first.url;
      metadata = await _metadataService.findMetadataForAlbum(firstTrackUrl);
    }

    if (metadata != null) {
      final enrichedAlbum = Album(
        id: album.id,
        title: metadata.title.isNotEmpty ? metadata.title : album.title,
        artist: metadata.artist.isNotEmpty ? metadata.artist : album.artist,
        coverUrl: metadata.imageUrl ?? album.coverUrl,
        tracks: album.tracks,
        description: metadata.description,
        published: metadata.published,
      );

      // Overwrite the enriched album in all feeds/maps
      final m = await _loadMap();
      bool updated = false;
      for (final feedId in m.keys) {
        final list = m[feedId] ?? [];
        final idx = list.indexWhere((a) => a.id == album.id);
        if (idx >= 0) {
          list[idx] = enrichedAlbum;
          updated = true;
        }
      }
      if (updated) {
        await _saveMap(m);
      }
    }
  }

  Future<Map<String, List<Album>>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as List<dynamic>).map((e) => Album.fromMap(Map<String, dynamic>.from(e))).toList()));
  }

  Future<void> _saveMap(Map<String, List<Album>> map) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(map.map((k, v) => MapEntry(k, v.map((a) => a.toMap()).toList())));
    await prefs.setString(_key, encoded);
  }

  Future<List<Album>> getAlbumsForFeed(String feedId) async {
    final m = await _loadMap();
    return m[feedId] ?? [];
  }

  Future<List<Album>> getAllAlbums() async {
    // Ensure migrated titles are normalized once before returning albums.
    await _ensureStoredTitlesNormalized();
    final m = await _loadMap();
    return m.values.expand((e) => e).toList();
  }

  Future<bool> albumExists(String albumId) async {
    final m = await _loadMap();
    // Check if album exists in any feed
    for (final list in m.values) {
      if (list.any((a) => a.id == albumId)) {
        return true;
      }
    }
    return false;
  }

  Future<void> saveAlbum(String feedId, Album album) async {
    // Check if this album already exists in any feed
    final exists = await albumExists(album.id);
    if (exists) {
      debugPrint('Album "${album.title}" already exists, skipping duplicate');
      return;
    }

    // Try to enrich album with metadata from RSS/Atom feed
    final tracks = album.tracks;
    if (tracks.isNotEmpty) {
      final firstTrackUrl = tracks.first.url;
      final metadata = await _metadataService.findMetadataForAlbum(firstTrackUrl);
      if (metadata != null) {
        // Create enriched album with RSS metadata
        album = Album(
          id: album.id,
          title: metadata.title.isNotEmpty ? metadata.title : album.title,
          artist: album.artist,
          coverUrl: metadata.imageUrl ?? album.coverUrl,
          tracks: album.tracks,
          description: metadata.description,
          published: metadata.published,
        );
      }
    }

    final m = await _loadMap();
    final list = m[feedId] ?? [];
    // replace if same id (shouldn't happen now due to check above, but keep for safety)
    final idx = list.indexWhere((a) => a.id == album.id);
    if (idx >= 0) {
      list[idx] = album;
    } else {
      list.add(album);
    }
    m[feedId] = list;
    await _saveMap(m);
  }
}
