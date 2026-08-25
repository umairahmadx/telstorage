/*
 * File: navigation_service.dart
 * Description: Component and logic definition for navigation_service.dart in TelStorage.
 */

import 'package:flutter/material.dart';
import '../navigation/navigation_intent.dart';

class NavigationService {
  NavigationService._();
  static final NavigationService instance = NavigationService._();

  final ValueNotifier<NavigationIntent?> _currentIntent = ValueNotifier(null);
  ValueNotifier<NavigationIntent?> get intentNotifier => _currentIntent;

  int _lastTransferTab = 0;
  int get lastTransferTab => _lastTransferTab;

  void setIntent(NavigationIntent intent) {
    _currentIntent.value = intent;

    // If it's a transfer intent, update the remembered state
    final transferTab = intent.transferTabIndex;
    if (transferTab != null) {
      _lastTransferTab = transferTab;
    }
  }

  void updateRememberedTransferTab(int index) {
    _lastTransferTab = index;
  }

  void clearIntent() {
    _currentIntent.value = null;
  }

  /// High-level method for callers
  void navigateTo(AppDestination destination, {Map<String, dynamic>? args}) {
    setIntent(NavigationIntent(destination: destination, arguments: args));
  }
}
