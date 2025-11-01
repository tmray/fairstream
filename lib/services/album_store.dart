
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
  static const _artistFixMigrationKey = 'albums_artist_fix_v1';

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

  /// One-time migration to correct albums where the artist was incorrectly set
  /// to the album title (common when RSS channel title lacks an "Artist - Album" pattern).
  /// Attempts to fetch metadata using the first track URL to resolve the real artist.
  Future<void> _ensureArtistsFixed() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(_artistFixMigrationKey) ?? false;
    if (migrated) return;

    final m = await _loadMap();
    var changed = false;
    for (final feedId in m.keys) {
      final list = m[feedId] ?? [];
      for (var i = 0; i < list.length; i++) {
        final album = list[i];
        final artist = album.artist.trim();
        final title = album.title.trim();
        var looksWrong = artist.isEmpty || artist.toLowerCase() == title.toLowerCase();
        if (!looksWrong) {
          // Also consider it wrong if title looks like "Artist - Album" and artist equals the album part
          final cleanedTitle = cleanTrackTitle(title);
          final dashIdx0 = cleanedTitle.indexOf('-');
          if (dashIdx0 > 0) {
            final left0 = cleanedTitle.substring(0, dashIdx0).trim();
            final right0 = cleanedTitle.substring(dashIdx0 + 1).trim();
            if (artist.toLowerCase() == right0.toLowerCase() && left0.isNotEmpty) {
              looksWrong = true;
            }
          }
          if (!looksWrong) continue;
        }

        // Quick heuristic: if title looks like "Artist - Album" and artist equals the album part,
        // swap to use the artist part and clean the title to just album.
  final cleanedTitle = cleanTrackTitle(album.title);
        final dashIdx = cleanedTitle.indexOf('-');
        if (dashIdx > 0) {
          final left = cleanedTitle.substring(0, dashIdx).trim();
          final right = cleanedTitle.substring(dashIdx + 1).trim();
          if (artist.toLowerCase() == right.toLowerCase()) {
            list[i] = Album(
              id: album.id,
              title: right,
              artist: left,
              coverUrl: album.coverUrl,
              tracks: album.tracks,
              description: album.description,
              published: album.published,
            );
            changed = true;
            continue;
          }
        }

        // Try feed metadata using the first track URL (most reliable)
        FeedMetadata? metadata;
        try {
          if (album.tracks.isNotEmpty) {
            metadata = await _metadataService.findMetadataForAlbum(album.tracks.first.url);
          }
          // As a fallback, try album.id which may contain a URL in M3U case
          metadata ??= await _metadataService.findMetadataForAlbum(album.id);
        } catch (_) {}

        if (metadata != null && metadata.artist.isNotEmpty) {
          // If metadata title is combined, strip the artist prefix to keep album-only title
          var newTitle = album.title;
          if (metadata.title.isNotEmpty) {
            final cleaned = cleanTrackTitle(metadata.title);
            final hyphenIdx = cleaned.indexOf('-');
            if (hyphenIdx > 0) {
              final left = cleaned.substring(0, hyphenIdx).trim();
              final right = cleaned.substring(hyphenIdx + 1).trim();
              if (left.toLowerCase() == metadata.artist.toLowerCase()) {
                newTitle = right;
              } else {
                newTitle = cleaned;
              }
            } else {
              newTitle = cleaned;
            }
          }
          list[i] = Album(
            id: album.id,
            title: newTitle.isNotEmpty ? newTitle : album.title,
            artist: metadata.artist,
            coverUrl: metadata.imageUrl ?? album.coverUrl,
            tracks: album.tracks,
            description: metadata.description ?? album.description,
            published: metadata.published ?? album.published,
          );
          changed = true;
        }
      }
      m[feedId] = list;
    }

    if (changed) {
      await _saveMap(m);
    }
    await prefs.setBool(_artistFixMigrationKey, true);
  }

  /// Public repair utility to fix artist names across the library on-demand.
  /// Returns the number of albums updated. This is more aggressive than the
  /// one-time migration and can be invoked from UI.
  Future<int> repairArtistMetadata() async {
    final m = await _loadMap();
    var changed = 0;
    for (final feedId in m.keys) {
      final list = m[feedId] ?? [];
      for (var i = 0; i < list.length; i++) {
        var album = list[i];
        final artist = album.artist.trim();
        final title = album.title.trim();
        var needsFix = artist.isEmpty || artist.toLowerCase() == title.toLowerCase();
        if (!needsFix) {
          final cleanedTitle0 = cleanTrackTitle(title);
          final dashIdx = cleanedTitle0.indexOf('-');
          if (dashIdx > 0) {
            final left = cleanedTitle0.substring(0, dashIdx).trim();
            final right = cleanedTitle0.substring(dashIdx + 1).trim();
            if (artist.toLowerCase() == right.toLowerCase() && left.isNotEmpty) {
              needsFix = true;
            }
          }
          if (!needsFix) continue;
        }

        String? fixedArtist;
        String? fixedTitle;
        String? fixedCover;
        String? fixedDescription;
        String? fixedPublished;

        // Heuristic first: if title looks like "Artist - Album" and current artist matches the album portion,
        // correct immediately without network.
        final cleanedTitle = cleanTrackTitle(album.title);
        final dashIdx2 = cleanedTitle.indexOf('-');
        if (dashIdx2 > 0) {
          final left = cleanedTitle.substring(0, dashIdx2).trim();
          final right = cleanedTitle.substring(dashIdx2 + 1).trim();
          if (artist.isEmpty || artist.toLowerCase() == right.toLowerCase()) {
            fixedArtist = left;
            fixedTitle = right;
          }
        }

        // Try metadata by first track URL, then by album id (may be URL)
        FeedMetadata? metadata;
        try {
          if (fixedArtist == null && album.tracks.isNotEmpty) {
            metadata = await _metadataService.findMetadataForAlbum(album.tracks.first.url);
          }
          if (fixedArtist == null) {
            metadata ??= await _metadataService.findMetadataForAlbum(album.id);
          }
        } catch (_) {}

        if (metadata != null) {
          if ((fixedArtist == null || fixedArtist.isEmpty) && metadata.artist.isNotEmpty) fixedArtist = metadata.artist;
          if ((fixedTitle == null || fixedTitle.isNotEmpty == false) && metadata.title.isNotEmpty) {
            final cleaned = cleanTrackTitle(metadata.title);
            final hyphenIdx = cleaned.indexOf('-');
            if (hyphenIdx > 0 && fixedArtist != null && fixedArtist.isNotEmpty) {
              final left = cleaned.substring(0, hyphenIdx).trim();
              final right = cleaned.substring(hyphenIdx + 1).trim();
              fixedTitle = (left.toLowerCase() == fixedArtist.toLowerCase()) ? right : cleaned;
            } else {
              fixedTitle = cleaned;
            }
          }
          fixedCover = metadata.imageUrl ?? fixedCover;
          fixedDescription = metadata.description ?? fixedDescription;
          fixedPublished = metadata.published ?? fixedPublished;
        }

        // If still no artist, try inferring from first track title like "Artist - Track"
        if ((fixedArtist == null || fixedArtist.trim().isEmpty) && album.tracks.isNotEmpty) {
          final t0 = album.tracks.first.title;
          final cleaned = cleanTrackTitle(t0);
          if (cleaned.contains('-')) {
            final parts = cleaned.split('-');
            final inferred = parts.first.trim();
            if (inferred.isNotEmpty && inferred.toLowerCase() != title.toLowerCase()) {
              fixedArtist = inferred;
            }
          }
        }

        if (fixedArtist != null && fixedArtist.trim().isNotEmpty && fixedArtist.trim().toLowerCase() != artist.toLowerCase()) {
          // Apply fixes
          album = Album(
            id: album.id,
            title: (fixedTitle != null && fixedTitle.trim().isNotEmpty) ? fixedTitle : album.title,
            artist: fixedArtist,
            coverUrl: fixedCover ?? album.coverUrl,
            tracks: album.tracks,
            description: fixedDescription ?? album.description,
            published: fixedPublished ?? album.published,
          );
          list[i] = album;
          changed++;
        }
      }
      m[feedId] = list;
    }

    if (changed > 0) {
      await _saveMap(m);
    }
    return changed;
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
    await _ensureArtistsFixed();
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
        // Prefer metadata artist if present
        var newArtist = metadata.artist.isNotEmpty ? metadata.artist : album.artist;

        // If metadata title looks like "Artist - Album" and we know artist,
        // extract just the album portion for a cleaner title.
        var newTitle = album.title;
        if (metadata.title.isNotEmpty) {
          final cleaned = cleanTrackTitle(metadata.title);
          final hyphenIdx = cleaned.indexOf('-');
          if (hyphenIdx > 0) {
            final left = cleaned.substring(0, hyphenIdx).trim();
            final right = cleaned.substring(hyphenIdx + 1).trim();
            if (newArtist.isNotEmpty && left.toLowerCase() == newArtist.toLowerCase()) {
              newTitle = right;
            } else {
              newTitle = cleaned;
            }
          } else {
            newTitle = cleaned;
          }
        }

        // Create enriched album with RSS metadata
        album = Album(
          id: album.id,
          title: newTitle,
          artist: newArtist,
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
