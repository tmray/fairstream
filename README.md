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

### Navigation
- **Tab-Based Interface**: Four main tabs (Search, Library, Artists, Import)
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
- Migration system ensures data integrity across app updates

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
├── screens/          # UI screens (Home, AlbumDetail, ArtistDetail, etc.)
├── services/         # Business logic
│   ├── album_store.dart       # Persistent storage & migrations
│   ├── m3u_parser.dart        # M3U playlist parsing
│   ├── feed_parser.dart       # RSS/Atom feed parsing
│   ├── feed_metadata.dart     # Metadata enrichment
│   ├── playback_manager.dart  # Audio playback control
│   └── text_normalizer.dart   # String cleaning utilities
└── widgets/          # Reusable UI components
```

## Development Philosophy

FairStream is designed as a **client-only application** with no backend server. Each user imports and manages their own library locally. This approach:

- ✅ Respects user privacy (no centralized tracking)
- ✅ Puts users in control of their library
- ✅ Reduces infrastructure costs and complexity

## Contributing

This is an independent project built for personal use and learning. Feel free to fork and adapt for your own needs!
