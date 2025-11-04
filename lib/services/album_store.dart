
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/album.dart';
import '../models/track.dart';
import 'feed_metadata.dart';
import 'feed_parser.dart';
import 'text_normalizer.dart';

class AlbumStore {
  final _metadataService = FeedMetadataService();

  static const _key = 'albums_all';
  static const _migrationKey = 'albums_normalized_v2';
  static const _artistFixMigrationKey = 'albums_artist_fix_v1';
  static const _albumsVersionKey = 'albums_version_v1';
  static const _artistsIndexKey = 'artists_index_v1';
  static const _dupeCleanupMigrationKey = 'albums_dupe_cleanup_v1';
  static const _titleFixMigrationKey = 'albums_title_fix_v1';

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
      // Fallback cover heuristic if feed lacks an image or current cover is a banner from root M3U
      String? fallbackCover() {
        Uri? u;
        try {
          u = Uri.parse(album.id.split('#').first);
        } catch (_) {}
        if (u == null || u.host.isEmpty || u.pathSegments.isEmpty || u.pathSegments.first == 'playlist.m3u') {
          try {
            final t = Uri.parse(album.tracks.first.url);
            if (t.host.isNotEmpty && t.pathSegments.isNotEmpty) {
              u = Uri(scheme: t.scheme, host: t.host, pathSegments: [t.pathSegments.first, 'cover_480.jpg']);
            }
          } catch (_) {}
        } else {
          u = Uri(scheme: u.scheme, host: u.host, pathSegments: [u.pathSegments.first, 'cover_480.jpg']);
        }
        return u?.toString();
      }
    final coverToUse = (metadata.imageUrl != null && metadata.imageUrl!.isNotEmpty)
      ? metadata.imageUrl
      : (fallbackCover() ?? album.coverUrl);
      final enrichedAlbum = Album(
        id: album.id,
        title: album.title, // Keep M3U album title (from #EXTALB)
        artist: album.artist, // Keep M3U artist (from #PLAYLIST)
        coverUrl: coverToUse,
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

  // ------------ M3U Cover Repair ------------

  String? _derivedCoverFromAlbum(Album album) {
    Uri? u;
    try {
      u = Uri.parse(album.id.split('#').first);
    } catch (_) {}
    if (u == null || u.host.isEmpty || u.pathSegments.isEmpty || u.pathSegments.first == 'playlist.m3u') {
      try {
        if (album.tracks.isNotEmpty) {
          final t = Uri.parse(album.tracks.first.url);
          if (t.host.isNotEmpty && t.pathSegments.isNotEmpty) {
            return Uri(scheme: t.scheme, host: t.host, pathSegments: [t.pathSegments.first, 'cover_480.jpg']).toString();
          }
        }
      } catch (_) {}
    } else {
      return Uri(scheme: u.scheme, host: u.host, pathSegments: [u.pathSegments.first, 'cover_480.jpg']).toString();
    }
    return null;
  }

  bool _looksLikeBanner(String? url) => (url ?? '').contains('image_fixed_');

  /// Repairs album cover for a single album using M3U-derived slug cover.
  /// Returns true if updated and saved.
  Future<bool> repairCoverForAlbum(Album album) async {
    final derived = _derivedCoverFromAlbum(album);
    if (derived == null) return false;
    final needs = album.coverUrl == null || album.coverUrl!.isEmpty || _looksLikeBanner(album.coverUrl);
    if (!needs && album.coverUrl == derived) return false;

    final m = await _loadMap();
    var changed = false;
    m.forEach((feedId, list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == album.id) {
          list[i] = Album(
            id: list[i].id,
            title: list[i].title,
            artist: list[i].artist,
            coverUrl: derived,
            tracks: list[i].tracks,
            description: list[i].description,
            published: list[i].published,
          );
          changed = true;
        }
      }
    });
    if (changed) {
      await _saveMap(m);
    }
    return changed;
  }

  /// Repairs album covers across the library using M3U-derived slug cover when
  /// the current image looks like a banner or is missing. Returns count updated.
  Future<int> repairAlbumCoversFromM3U() async {
    final m = await _loadMap();
    var updated = 0;
    m.forEach((feedId, list) {
      for (var i = 0; i < list.length; i++) {
        final a = list[i];
        final derived = _derivedCoverFromAlbum(a);
        if (derived == null) continue;
        final needs = a.coverUrl == null || a.coverUrl!.isEmpty || _looksLikeBanner(a.coverUrl);
        if (needs || a.coverUrl != derived) {
          list[i] = Album(
            id: a.id,
            title: a.title,
            artist: a.artist,
            coverUrl: derived,
            tracks: a.tracks,
            description: a.description,
            published: a.published,
          );
          updated++;
        }
      }
    });
    if (updated > 0) {
      await _saveMap(m);
    }
    return updated;
  }

  // ------------ M3U Track Title Repair ------------

  String? _albumLevelPlaylistUrl(Album album) {
    // Try from album.id
    try {
      final u0 = Uri.parse(album.id.split('#').first);
      if (u0.host.isNotEmpty && u0.pathSegments.isNotEmpty) {
        final slug = u0.pathSegments.first;
        if (slug.isNotEmpty && slug != 'playlist.m3u') {
          return Uri(scheme: u0.scheme, host: u0.host, pathSegments: [slug, 'playlist.m3u']).toString();
        }
      }
    } catch (_) {}
    // Fallback to first track URL
    if (album.tracks.isNotEmpty) {
      try {
        final t = Uri.parse(album.tracks.first.url);
        if (t.host.isNotEmpty && t.pathSegments.isNotEmpty) {
          final slug = t.pathSegments.first;
          if (slug.isNotEmpty && slug != 'playlist.m3u') {
            return Uri(scheme: t.scheme, host: t.host, pathSegments: [slug, 'playlist.m3u']).toString();
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Re-parse the album-level M3U for this album and replace track titles.
  /// Useful to fix legacy imports where #EXTINF titles were truncated at commas.
  /// Returns true if tracks were updated and saved.
  Future<bool> repairTrackTitlesFromM3U(Album album) async {
    final playlist = _albumLevelPlaylistUrl(album);
    if (playlist == null) return false;
    try {
      // Parse the album-level playlist which should yield exactly one album for the slug
      final parser = FeedParser();
      final parsed = await parser.parseFeed(playlist);
      if (parsed.isEmpty) return false;

      // Match on canonical key to be safe
      final targetKey = _canonicalKeyForAlbum(album);
      Album? updated;
      for (final a in parsed) {
        final k = _canonicalKeyForAlbum(a);
        if (k != null && k == targetKey) {
          updated = a;
          break;
        }
      }
      updated ??= parsed.first;

      // If no change in tracks, skip
      if (updated.tracks.length == album.tracks.length &&
          List.generate(updated.tracks.length, (i) => updated!.tracks[i].title == album.tracks[i].title).every((e) => e)) {
        return false;
      }

      final m = await _loadMap();
      var changed = false;
      m.forEach((feedId, list) {
        for (var i = 0; i < list.length; i++) {
          if (list[i].id == album.id) {
            list[i] = Album(
              id: list[i].id,
              title: list[i].title,
              artist: list[i].artist,
              coverUrl: list[i].coverUrl,
              tracks: updated!.tracks,
              description: list[i].description,
              published: list[i].published,
            );
            changed = true;
          }
        }
      });
      if (changed) {
        await _saveMap(m);
      }
      return changed;
    } catch (_) {
      return false;
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
    // Bump albums version so dependent caches (like artist index) know to invalidate
    final current = prefs.getInt(_albumsVersionKey) ?? 0;
    await prefs.setInt(_albumsVersionKey, current + 1);
    // Invalidate artist index cache (lazy rebuild on next request)
    await prefs.remove(_artistsIndexKey);
  }

  Future<List<Album>> getAlbumsForFeed(String feedId) async {
    final m = await _loadMap();
    return m[feedId] ?? [];
  }

  Future<List<Album>> getAllAlbums() async {
    // Ensure migrated titles are normalized once before returning albums.
    await _ensureStoredTitlesNormalized();
    await _ensureArtistsFixed();
    await _ensureDuplicateCleanup();
    await _ensureAlbumTitlesFixed();
    final m = await _loadMap();
    return m.values.expand((e) => e).toList();
  }

  // ------------ Cached Artist Index ------------

  int _normalizeVersion(int? v) => v ?? 0;

  String _artistKey(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<Map<String, dynamic>?> _loadArtistIndexRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_artistsIndexKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveArtistIndexRaw(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_artistsIndexKey, jsonEncode(data));
  }

  Future<Map<String, ArtistIndexEntry>> getArtistIndexCached() async {
    final prefs = await SharedPreferences.getInstance();
    final albumsVersion = _normalizeVersion(prefs.getInt(_albumsVersionKey));

    // Try cache
    final raw = await _loadArtistIndexRaw();
    if (raw != null) {
      final cachedVersion = _normalizeVersion(raw['version'] as int?);
      final groupsRaw = raw['groups'];
      if (cachedVersion == albumsVersion && groupsRaw is Map<String, dynamic>) {
        final result = <String, ArtistIndexEntry>{};
        groupsRaw.forEach((k, v) {
          final m = v as Map<String, dynamic>;
          result[k] = ArtistIndexEntry(
            displayName: (m['displayName'] as String?) ?? k,
            albumIds: ((m['albumIds'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
          );
        });
        return result;
      }
    }

    // Build fresh
    final albums = await getAllAlbums();
    final groups = <String, ArtistIndexEntry>{};
    for (final a in albums) {
      final key = _artistKey(a.artist);
      if (key.isEmpty) continue;
      final g = groups.putIfAbsent(key, () => ArtistIndexEntry(displayName: a.artist, albumIds: []));
      g.albumIds.add(a.id);
      if (a.artist.trim().length > g.displayName.trim().length) {
        g.displayName = a.artist;
      }
    }

    // Persist with current albums version
    final groupsJson = groups.map((k, v) => MapEntry(k, v.toJson()));
    await _saveArtistIndexRaw({
      'version': albumsVersion,
      'groups': groupsJson,
    });

    return groups;
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

  /// Compute a canonical key for an album to detect duplicates across
  /// root-level and album-level Faircamp M3U playlists.
  /// Prefers deriving from the first track URL; falls back to album ID URL.
  String? _canonicalKeyForAlbum(Album album) {
    String? fromUrl(String url) {
      try {
        final u = Uri.parse(url);
        if (u.host.isEmpty) return null;
        if (u.pathSegments.isEmpty) return null;
        final slug = u.pathSegments.first;
        if (slug.isEmpty || slug == 'playlist.m3u') return null;
        return '${u.scheme}://${u.host}/$slug';
      } catch (_) {
        return null;
      }
    }

    // Try from first track url
    if (album.tracks.isNotEmpty) {
      final k = fromUrl(album.tracks.first.url);
      if (k != null) return k;
    }
    // Try from album id before '#'
    final id = album.id.split('#').first;
    final k2 = fromUrl(id);
    return k2;
  }

  /// Cross-feed duplicate check using canonical key derived from URLs.
  Future<bool> albumExistsCanonical(Album album) async {
    final key = _canonicalKeyForAlbum(album);
    if (key == null) return await albumExists(album.id);
    final m = await _loadMap();
    for (final list in m.values) {
      for (final a in list) {
        final ak = _canonicalKeyForAlbum(a);
        if (ak != null && ak == key) return true;
      }
    }
    return false;
  }

  /// One-time cleanup to remove any pre-existing duplicates that may have
  /// been imported before canonical dedupe logic existed.
  Future<void> _ensureDuplicateCleanup() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(_dupeCleanupMigrationKey) ?? false;
    if (migrated) return;
    try {
      await cleanupCanonicalDuplicates();
    } catch (_) {}
    await prefs.setBool(_dupeCleanupMigrationKey, true);
  }

  /// One-time migration to fix album titles that were enriched from RSS feeds
  /// with "Artist - Album" format. Extracts just the album name portion.
  Future<void> _ensureAlbumTitlesFixed() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(_titleFixMigrationKey) ?? false;
    if (migrated) return;

    final m = await _loadMap();
    var changed = false;
    for (final feedId in m.keys) {
      final list = m[feedId] ?? [];
      for (var i = 0; i < list.length; i++) {
        final album = list[i];
        final title = album.title.trim();
        
        // Check if title is in "Artist - Album" format
        final dashIdx = title.indexOf(' - ');
        if (dashIdx > 0) {
          final leftPart = title.substring(0, dashIdx).trim();
          final rightPart = title.substring(dashIdx + 3).trim();
          
          // If left part matches the artist, extract just the album (right part)
          if (leftPart.toLowerCase() == album.artist.toLowerCase() && rightPart.isNotEmpty) {
            list[i] = Album(
              id: album.id,
              title: rightPart,
              artist: album.artist,
              coverUrl: album.coverUrl,
              tracks: album.tracks,
              description: album.description,
              published: album.published,
            );
            changed = true;
          }
        }
      }
      if (changed) {
        m[feedId] = list;
      }
    }

    if (changed) {
      await _saveMap(m);
    }
    await prefs.setBool(_titleFixMigrationKey, true);
  }

  /// Remove existing duplicate albums across feeds based on canonical identity
  /// (scheme://host/slug). Keeps the "best" representative and removes others.
  /// Returns stats about how many were removed.
  Future<DuplicateCleanupResult> cleanupCanonicalDuplicates() async {
    final m = await _loadMap();
    // Build groups of albums by canonical key
  final groups = <String, List<_LocatedAlbum>>{};
    m.forEach((feedId, list) {
      for (final a in list) {
        final key = _canonicalKeyForAlbum(a);
        if (key == null) continue;
  final g = groups.putIfAbsent(key, () => <_LocatedAlbum>[]);
        g.add(_LocatedAlbum(feedId: feedId, album: a));
      }
    });

    int removed = 0;
    int kept = 0;
    int groupsAffected = 0;
    final removals = <String, Set<String>>{}; // feedId -> albumIds

    int quality(Album a) {
      var score = 0;
      // Prefer album-level IDs (contain slug path segment before playlist.m3u)
      try {
        final u = Uri.parse(a.id.split('#').first);
        if (u.host.isNotEmpty && u.pathSegments.isNotEmpty) {
          final segs = u.pathSegments;
          // album-level looks like [slug, 'playlist.m3u']
          if (segs.length >= 2 && segs.first.isNotEmpty && segs.last.endsWith('.m3u')) {
            score += 3;
          } else if (segs.length == 1 && segs.first == 'playlist.m3u') {
            score += 0;
          }
        }
      } catch (_) {}
      if ((a.coverUrl ?? '').isNotEmpty) score += 5;
      if ((a.description ?? '').isNotEmpty) score += 3;
      if ((a.published ?? '').isNotEmpty) score += 1;
      score += a.tracks.length; // prefer more tracks
      return score;
    }

    for (final entry in groups.entries) {
      final dupes = entry.value;
      if (dupes.length <= 1) continue;
      groupsAffected++;
      // choose best by quality
      dupes.sort((a, b) => quality(b.album).compareTo(quality(a.album)));
      final best = dupes.first.album;
      // Merge best cover and description from all dupes
      // Always pick the richest cover and description from all dupes
      String? bestCover = best.coverUrl;
      String? bestDesc = best.description;
      String? bestPublished = best.published;
      int coverScore = (bestCover ?? '').length;
      int descScore = (bestDesc ?? '').length;
      int pubScore = (bestPublished ?? '').length;
      for (final d in dupes) {
        final c = d.album.coverUrl;
        if ((c ?? '').isNotEmpty && (c?.length ?? 0) > coverScore) {
          bestCover = c;
          coverScore = c!.length;
        }
        final desc = d.album.description;
        if ((desc ?? '').isNotEmpty && (desc?.length ?? 0) > descScore) {
          bestDesc = desc;
          descScore = desc!.length;
        }
        final pub = d.album.published;
        if ((pub ?? '').isNotEmpty && (pub?.length ?? 0) > pubScore) {
          bestPublished = pub;
          pubScore = pub!.length;
        }
      }
      // If best is missing cover/desc/published, update it in place in the map
      for (final d in dupes) {
        if (d.album.id == best.id) {
          final feedId = d.feedId;
          final list = m[feedId] ?? [];
          final idx = list.indexWhere((a) => a.id == best.id);
          if (idx >= 0) {
            list[idx] = Album(
              id: best.id,
              title: best.title,
              artist: best.artist,
              coverUrl: bestCover,
              tracks: best.tracks,
              description: bestDesc,
              published: bestPublished,
            );
            m[feedId] = list;
            // After merging, force refresh metadata from feed for canonical album
            try {
              await refreshAlbumMetadata(list[idx]);
            } catch (_) {}
          }
        }
      }
      kept++;
      for (final d in dupes.skip(1)) {
        final set = removals.putIfAbsent(d.feedId, () => <String>{});
        set.add(d.album.id);
        removed++;
      }
    }

    if (removed == 0) {
      return DuplicateCleanupResult(groupsAffected: 0, removed: 0, kept: 0);
    }

    // Apply removals
    removals.forEach((feedId, ids) {
      final list = m[feedId] ?? [];
      m[feedId] = list.where((a) => !ids.contains(a.id)).toList();
    });
    await _saveMap(m);
    return DuplicateCleanupResult(groupsAffected: groupsAffected, removed: removed, kept: kept);
  }

  Future<void> saveAlbum(String feedId, Album album) async {
    // Check if this album already exists in any feed (canonical check)
    final exists = await albumExistsCanonical(album);
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

class ArtistIndexEntry {
  ArtistIndexEntry({required this.displayName, required this.albumIds});
  String displayName;
  final List<String> albumIds;

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'albumIds': albumIds,
      };
}

/// Result of a duplicate cleanup pass.
class DuplicateCleanupResult {
  final int groupsAffected;
  final int removed;
  final int kept;
  const DuplicateCleanupResult({required this.groupsAffected, required this.removed, required this.kept});
}

class _LocatedAlbum {
  final String feedId;
  final Album album;
  _LocatedAlbum({required this.feedId, required this.album});
}

