import 'package:flutter/material.dart';
import 'library_screen.dart';
import 'feeds_screen.dart';
import 'artists_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  // Navigation keys for each tab - allows each tab to maintain its own navigation stack
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(), // Search
    GlobalKey<NavigatorState>(), // Library
    GlobalKey<NavigatorState>(), // Artists
    GlobalKey<NavigatorState>(), // Feeds
  ];

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
              _buildNavigator(1, const LibraryScreen()),
              _buildNavigator(2, const ArtistsScreen()),
              _buildNavigator(3, const FeedsScreen()),
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
              setState(() => _selectedIndex = index);
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.library_music), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.group), label: 'Artists'),
            NavigationDestination(icon: Icon(Icons.playlist_add), label: 'Import'),
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