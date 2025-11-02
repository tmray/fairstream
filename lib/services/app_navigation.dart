import 'package:flutter/foundation.dart';

/// Global app navigation state for managing the persistent bottom navigation bar.
///
/// Screens can listen to [currentIndex] to react to tab changes and update
/// their content accordingly. The global navigation bar overlay updates this
/// value and also pops to the root route when switching tabs, so the main
/// HomeScreen is visible.
class AppNavigation {
  AppNavigation._();
  static final AppNavigation instance = AppNavigation._();

  /// The currently selected bottom navigation tab index.
  final ValueNotifier<int> currentIndex = ValueNotifier<int>(0);

  void setIndex(int index) {
    if (index == currentIndex.value) return;
    currentIndex.value = index;
  }
}
