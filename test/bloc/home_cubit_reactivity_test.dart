import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/features/browser/bloc/browser_state.dart';

void main() {
  test('browser state preserves reactive updates through copyWith', () {
    final initial = BrowserState(isInitialized: true);
    final updated = initial.copyWith(
      isLoading: true,
      searchQuery: 'report',
      isOffline: true,
    );

    expect(updated.isInitialized, isTrue);
    expect(updated.isLoading, isTrue);
    expect(updated.searchQuery, 'report');
    expect(updated.isOffline, isTrue);
  });
}
