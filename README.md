# FairStream

A Flutter-based music streaming app for Faircamp-hosted music collections. FairStream allows you to discover, stream, and organize music from independent artists who host their albums using the Faircamp platform.

## Overview

FairStream is a client application that connects to Faircamp music servers (like `https://faircamp.examplesite.com`) by parsing M3U playlists and RSS/Atom feeds. It provides sections for browsing artists, albums, and tracks in local storage and background audio playback.

### The Podcast Model for Music Streaming

FairStream explores a different approach to music streaming by adapting the podcast model:

**How Podcasts Work:**
- Podcasters host their content on their own servers or hosting services
- They publish an RSS feed URL
- Listeners add that feed URL to their podcast app of choice
- No central platform controls access or takes a cut

**FairStream applies this to music:**
- Artists host their music on their own Faircamp sites
- They publish M3U playlists and RSS/Atom feeds
- Fans visit the artist's website and copy the M#U playlist URL
- Fans add that URL to FairStream to build their personal library
- Artists maintain control and direct relationships with their audience

This approach is looking to explore several possibilites:
- **Artist Independence**: Musicians control their distribution and presentation
- **Direct Discovery**: Fans find music through artist websites, social media, or word-of-mouth
- **No Platform Lock-in**: Users aren't tied to a single streaming service's catalog
- **Decentralized**: No central authority deciding what music is available
- **Standard Formats**: Uses existing web standards (M3U, RSS/Atom) rather than proprietary APIs

Just like podcast apps coexist (Apple Podcasts, Spotify, Pocket Casts, etc.) while all working with the same RSS feeds, FairStream demonstrates that music streaming could work the same way—with artists hosting their content and listeners choosing their preferred client app.

## Key Features

### Music Library
- **Import Albums**: Add albums via M3U playlist URLs from any Faircamp site that chooses to display them
- **Automatic Metadata**: Fetches album art, descriptions, and publishing dates from RSS/Atom feeds
- **Canonical Deduplication**: Prevents duplicate albums when importing from both root-level and album-level playlists
- **Persistent Storage**: Your library is saved locally and still shows them even after app restarts

### Browsing & Discovery
- **Library View**: Grid layout of all imported albums with cover art
- **Artist Pages**: Organized view of albums grouped by artist with:
  - Full-width header image
  - Artist description and external Faircamp artist links
  - Chronologically sorted album grid
- **Album Detail Pages**: View tracks, play albums, and discover more by the same artist
- **Global Search**: Search across your entire library with search history

### Playback
- **Background Playback**: Continues playing when app is backgrounded
- **Media Controls**: System-level play/pause controls
- **Persistent Now Playing Bar**: Always accessible at the bottom of the screen

### Artist Support & Listening Time Tracking
- **Automatic Listening Time Tracking**: Records how long you listen to each artist per month
- **Support Tab with Smart Notifications**: 
  - When you've listened to an artist for 30+ minutes in a month, they appear in the Support tab
  - A badge notification appears on the Support tab to alert you about artists worth supporting
  - Badge clears when you view the tab (with a 1-hour cooldown to avoid spam)
- **Direct Support Links**: One-tap access to each artist's Faircamp site to donate or subscribe
- **Artist Discovery**: Shows listening stats (e.g., "1 hr 23 min this month") to help you identify artists you're enjoying most

This creates a natural connection between your listening habits and supporting independent artists—the more you enjoy their music, the more you're encouraged to contribute directly to them, without any platform taking a cut.

### Navigation
- **Tab-Based Interface**: Five main tabs (Search, Library, Artists, Support, Import)
- **Per-Tab Navigation Stacks**: Deep linking within each tab with back button support

## Technical Architecture

### Platform Support
- **Linux** (primary development target)
- **Android/iOS** (mobile support via just_audio)
- **Desktop-Ready**: Responsive layouts adapt to larger screens

### Core Technologies
- **Flutter/Dart** with Material 3 design
- **just_audio** just_audio_background for audio playback
- **SharedPreferences** for persistent local storage
- **http** for M3U and feed parsing

### Storage Strategy
- Albums stored in a feed-keyed map structure
- Artist index cached with version-based invalidation
- Search history kept locally
- Listening time tracked per artist with monthly periods
- Migration system ensures data integrity across app updates

### Backup & Restore
FairStream supports manual export and import of all locally stored data (albums, artist index, listening time, search history, migration flags) via a JSON backup file.

**How to Create a Backup**
1. Open the Import tab.
2. Tap the Export button in the Library Backup section.
3. A JSON file named `fairstream_backup_YYYY-MM-DDTHH-MM-SS.json` is written to your Downloads directory.

**Default Backup Locations**
- Linux/macOS/Windows: `~/Downloads/`
- Android: `/storage/emulated/0/Download/` (or external storage fallback)
- iOS: App Documents directory (accessible via Files app if enabled)

**Restore From Backup**
1. Open the Import tab.
2. Tap Import and select a previously exported backup file.
3. Restart the app to ensure all restored data (albums, support stats, etc.) is reloaded into memory.

**Backup File Format**
```json
{
  "version": 1,
  "timestamp": "2025-11-21T14:30:45",
  "data": {
    "albums_all": {"<feedId>": [/* album objects */]},
    "artists_index_v1": {/* artist grouping data */},
    "listening_time_v1": {"2025-11": {"artistKey": 1835}},
    "search_history_v1": ["lorenzo", "live"],
    "support_tab_last_viewed_v1": 1732200000,
    "albums_normalized_v2": true
  }
}
```
Only known keys are exported; unknown or future keys are ignored safely on import. The `version` field allows forward compatibility—newer backups won't import into older app versions.

**Current Limitations / Roadmap**
- Manual process (no automatic scheduled backups yet)
- No encryption (consider storing sensitive notes externally if needed)
- Cloud sync foundation exists (see `cloud_sync_service.dart`) but OAuth + remote storage integration is not yet implemented
- Future enhancements: selective restore, periodic auto-backups, optional encryption, Google Drive integration

### Catalog Export (Shareable)
For sharing your library publicly (e.g., on a static site), FairStream can export a lightweight catalog JSON containing only your feed links and display info—no personal listening history or app settings.

**How to Export a Catalog**
- Open the Import tab → tap `Export Catalog`.
- A JSON file named `fairstream_catalog_YYYY-MM-DDTHH-MM-SS.json` is written to your Downloads directory.

**Catalog JSON Format**
```json
{
  "catalogVersion": 1,
  "generatedAt": "2025-11-25T14:30:45",
  "feeds": [
    {
      "url": "https://artist.example/playlist.m3u",
      "name": "Artist Name or Album Title",
      "imageUrl": "https://artist.example/cover.jpg",
      "addedAt": "2025-10-05T12:01:00"
    }
  ]
}
```

**How Import Works with Catalogs**
- Use the regular `Import` button and select a catalog JSON.
- The app auto-detects the format and re-parses each `url` to populate albums.
- Duplicate albums are skipped automatically.

**Use on a Static Site**
- Host the catalog JSON file on your personal site to showcase your library.
- Visitors can download the JSON and import it into FairStream to follow the same feeds.
- Since it contains only feed links, it is safe to share and does not include private app data.

### Parsing & Metadata
- **M3U Parser**: Handles Faircamp playlist format (`#EXTM3U`, `#PLAYLIST`, `#EXTALB`, `#EXTINF`, `#EXTIMG`)
- **RSS/Atom Parser**: Enriches albums with descriptions, cover art, and publication dates
- **Canonical Album Identity**: Derived from URL scheme/host/slug for deduplication

## Getting Started

### Prerequisites
- Flutter SDK (3.0+)
- For Linux builds: `libmpv-dev` and audio dependencies

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd FairStreamApp

# Install dependencies
flutter pub get

# Run on Linux
flutter run -d linux

# Or run on your connected mobile device
flutter run
```

### Adding Music

1. Open the **Import** tab
2. Enter an M3U playlist URL from a Faircamp site:
   - Root-level: `https://faircamp.examplesite.com/playlist.m3u`
   - Album-level: `https://faircamp.examplesite.com/album-slug/playlist.m3u`
3. Tap **Add to Library**
4. The app will fetch and enrich the album metadata automatically

### Supported Faircamp Sites

Any Faircamp-hosted site with:
- M3U playlists at `/playlist.m3u` or `/album-slug/playlist.m3u`
- RSS feed at `/feed.rss` or Atom feed at `/feed.atom`

## Project Structure

```
lib/
├── models/           # Data models (Album, Track)
├── screens/          # UI screens (Home, AlbumDetail, ArtistDetail, SupportArtists, etc.)
├── services/         # Business logic
│   ├── album_store.dart       # Persistent storage & migrations
│   ├── m3u_parser.dart        # M3U playlist parsing
│   ├── feed_parser.dart       # RSS/Atom feed parsing
│   ├── feed_metadata.dart     # Metadata enrichment
│   ├── playback_manager.dart  # Audio playback control & listening time tracking
│   ├── listening_tracker.dart # Artist listening time tracking & support notifications
│   ├── backup_service.dart    # Export/import JSON backup functionality
│   ├── cloud_sync_service.dart# Foundation for future cloud sync (manual hooks)
│   └── text_normalizer.dart   # String cleaning utilities
└── widgets/          # Reusable UI components
```

## Development Philosophy

FairStream is designed as a **client-only application** with no backend server. Each user imports and manages their own library locally. This approach:

- Respects user privacy (no centralized tracking)
- Puts users in control of their library
- Reduces infrastructure costs and complexity

## Contributing

This is an independent project built for personal use and learning. Feel free to fork and adapt for your own needs!
