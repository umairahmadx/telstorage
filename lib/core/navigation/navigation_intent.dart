/*
 * File: navigation_intent.dart
 * Description: Component and logic definition for navigation_intent.dart in TelStorage.
 */

enum AppDestination {
  home,
  files,
  transferDownloads,
  transferUploads,
  transferShared,
  transferActive,
  settings,
}

class NavigationIntent {
  final AppDestination destination;
  final Map<String, dynamic>? arguments;

  const NavigationIntent({
    required this.destination,
    this.arguments,
  });

  /// Helper to get the main tab index in MobileShell
  int get shellIndex {
    switch (destination) {
      case AppDestination.home:
        return 0;
      case AppDestination.files:
        return 1;
      case AppDestination.transferDownloads:
      case AppDestination.transferUploads:
      case AppDestination.transferShared:
      case AppDestination.transferActive:
        return 3;
      case AppDestination.settings:
        return 4;
    }
  }

  /// Helper to get the internal tab index for the Transfer screen
  int? get transferTabIndex {
    switch (destination) {
      case AppDestination.transferDownloads:
        return 0;
      case AppDestination.transferUploads:
        return 1;
      case AppDestination.transferShared:
        return 2;
      default:
        return null;
    }
  }
}
