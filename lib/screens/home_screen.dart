import 'package:flutter/material.dart';
import 'library_screen.dart';
import 'feeds_screen.dart';
import 'artists_screen.dart';
// ...existing code...
// ...existing code...

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  // ...existing code...

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FairStreamApp'),
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.library_music), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.group), label: 'Artists'),
          NavigationDestination(icon: Icon(Icons.rss_feed), label: 'Feeds'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const LibraryScreen();
      case 1:
        return const ArtistsScreen();
      case 2:
        return const FeedsScreen();
      default:
        return const Center(child: Text('Unknown View')); 
    }
  }
}