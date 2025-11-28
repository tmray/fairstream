import 'package:flutter/material.dart';
import 'library_screen.dart';
import 'feeds_screen.dart';
import 'artists_screen.dart';
import 'search_screen.dart';
import 'support_artists.dart';
import '../services/listening_tracker.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _supportBadgeCount = 0;
  Timer? _badgeUpdateTimer;
  final _tracker = ListeningTracker();
  
  // GlobalKeys to access screen states for manual reload
  final _libraryKey = GlobalKey<LibraryScreenState>();
  final _artistsKey = GlobalKey<ArtistsScreenState>();
  
  // Navigation keys for each tab - allows each tab to maintain its own navigation stack
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(), // Search
    GlobalKey<NavigatorState>(), // Library
    GlobalKey<NavigatorState>(), // Artists
    GlobalKey<NavigatorState>(), // Support
    GlobalKey<NavigatorState>(), // Feeds
  ];

  @override
  void initState() {
    super.initState();
    _updateBadgeCount();
    // Check for badge updates every minute
    _badgeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateBadgeCount();
    });
  }

  @override
  void dispose() {
    _badgeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateBadgeCount() async {
    final count = await _tracker.getUnviewedSupportCount();
    if (mounted) {
      setState(() => _supportBadgeCount = count);
    }
  }

  void _reloadLibraryAndArtists() {
    _libraryKey.currentState?.reload();
    _artistsKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        // Try to pop the current tab's navigation stack
        final navigator = _navigatorKeys[_selectedIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        }
      },
      child: Scaffold(
        body: Padding(
          // Add padding at the bottom for the playbar that sits above the nav bar
          padding: const EdgeInsets.only(bottom: 60.0),
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _buildNavigator(0, const SearchScreen()),
              _buildNavigator(1, LibraryScreen(key: _libraryKey)),
              _buildNavigator(2, ArtistsScreen(key: _artistsKey)),
              _buildNavigator(3, const SupportArtists()),
              _buildNavigator(4, FeedsScreen(onLibraryChanged: _reloadLibraryAndArtists)),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            if (index == _selectedIndex) {
              // Reselecting the current tab: pop to that tab's root
              final nav = _navigatorKeys[index].currentState;
              if (nav != null) {
                while (nav.canPop()) {
                  nav.pop();
                }
              }
            } else {
              // Special rule: when selecting the Search tab, always return to its root
              if (index == 0) {
                final searchNav = _navigatorKeys[0].currentState;
                if (searchNav != null) {
                  while (searchNav.canPop()) {
                    searchNav.pop();
                  }
                }
              }
              
              // When selecting Support tab, mark as viewed and clear badge
              if (index == 3) {
                _tracker.markSupportTabViewed().then((_) {
                  _updateBadgeCount();
                });
              }
              
              setState(() => _selectedIndex = index);
            }
          },
          destinations: [
            const NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            const NavigationDestination(icon: Icon(Icons.library_music), label: 'Library'),
            const NavigationDestination(icon: Icon(Icons.group), label: 'Artists'),
            NavigationDestination(
              icon: _supportBadgeCount > 0
                  ? Badge(
                      label: Text('$_supportBadgeCount'),
                      child: const Icon(Icons.favorite),
                    )
                  : const Icon(Icons.favorite),
              label: 'Support',
            ),
            const NavigationDestination(icon: Icon(Icons.playlist_add), label: 'Import'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(
          builder: (context) => child,
        );
      },
    );
  }
}