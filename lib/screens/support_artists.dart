import 'package:flutter/material.dart';
import '../services/listening_tracker.dart';
import '../services/album_store.dart';
import '../services/feed_metadata.dart';
import 'artist_detail.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportArtists extends StatefulWidget {
  const SupportArtists({super.key});

  @override
  State<SupportArtists> createState() => _SupportArtistsState();
}

class _SupportArtistsState extends State<SupportArtists> with WidgetsBindingObserver {
  final _tracker = ListeningTracker();
  final _store = AlbumStore();
  final _metadataService = FeedMetadataService();
  
  bool _loading = true;
  List<SupportArtistEntry> _artists = [];
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isVisible) {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload when this screen becomes visible again
    if (_isVisible) {
      _load();
    }
  }

  @override
  void activate() {
    super.activate();
    _isVisible = true;
    // Reload data when returning to this tab
    _load();
  }

  @override
  void deactivate() {
    _isVisible = false;
    super.deactivate();
  }

  String _normalizeArtist(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _load() async {
    setState(() => _loading = true);
    
    // Get artists above threshold
    final aboveThreshold = await _tracker.getArtistsAboveThreshold();
    
    if (aboveThreshold.isEmpty) {
      setState(() {
        _artists = [];
        _loading = false;
      });
      return;
    }
    
    // Load all albums to get display names and find Faircamp links
    final allAlbums = await _store.getAllAlbums();
    final entries = <SupportArtistEntry>[];
    
    for (final entry in aboveThreshold.entries) {
      final artistKey = entry.key;
      final seconds = entry.value;
      
      // Find an album by this artist to get display name and artwork
      final artistAlbums = allAlbums.where((a) => _normalizeArtist(a.artist) == artistKey).toList();
      if (artistAlbums.isEmpty) continue;
      
      final displayName = artistAlbums.first.artist;
      final coverUrl = artistAlbums.first.coverUrl;
      
      // Try to get the Faircamp site URL from the first track
      String? faircampUrl;
      for (final album in artistAlbums) {
        if (album.tracks.isNotEmpty) {
          try {
            final trackUri = Uri.parse(album.tracks.first.url);
            faircampUrl = '${trackUri.scheme}://${trackUri.host}';
            break;
          } catch (_) {}
        }
      }
      
      // Try to get artist metadata for description and link
      String? description;
      String? artistLink;
      if (artistAlbums.first.tracks.isNotEmpty) {
        try {
          final meta = await _metadataService.findArtistChannelFromUrl(artistAlbums.first.tracks.first.url);
          description = meta?.description;
          artistLink = meta?.link;
        } catch (_) {}
      }
      
      entries.add(SupportArtistEntry(
        artistKey: artistKey,
        displayName: displayName,
        listeningSeconds: seconds,
        coverUrl: coverUrl,
        faircampUrl: faircampUrl ?? artistLink,
        description: description,
      ));
    }
    
    // Sort by listening time (descending)
    entries.sort((a, b) => b.listeningSeconds.compareTo(a.listeningSeconds));
    
    setState(() {
      _artists = entries;
      _loading = false;
    });
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Your Artists'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _artists.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No artists to support yet',
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Listen to music for 30+ minutes this month to see artists you might want to support!',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'You\'ve listened to these artists for 30+ minutes this month. Consider supporting them!',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    ..._artists.map((artist) => _buildArtistCard(context, artist)),
                  ],
                ),
    );
  }

  Widget _buildArtistCard(BuildContext context, SupportArtistEntry artist) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ArtistDetail(
                artistKey: artist.artistKey,
                displayName: artist.displayName,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artist artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: artist.coverUrl != null
                    ? Image.network(
                        artist.coverUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Container(
                          width: 80,
                          height: 80,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.person,
                            size: 32,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          size: 32,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              // Artist info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.headphones,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${ListeningTracker.formatDuration(artist.listeningSeconds)} this month',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (artist.description != null && artist.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        artist.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Support button
                    if (artist.faircampUrl != null)
                      FilledButton.icon(
                        onPressed: () => _openLink(artist.faircampUrl!),
                        icon: const Icon(Icons.favorite, size: 18),
                        label: const Text('Support on Faircamp'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text('No Faircamp link available'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SupportArtistEntry {
  final String artistKey;
  final String displayName;
  final int listeningSeconds;
  final String? coverUrl;
  final String? faircampUrl;
  final String? description;

  SupportArtistEntry({
    required this.artistKey,
    required this.displayName,
    required this.listeningSeconds,
    this.coverUrl,
    this.faircampUrl,
    this.description,
  });
}
