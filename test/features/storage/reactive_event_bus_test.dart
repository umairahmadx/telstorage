/// File: reactive_event_bus_test.dart
/// Description: Unit tests for DomainEventBus reactivity and typed event streaming.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/events/domain_event_bus.dart';

void main() {
  test('event bus emits events reactively to typed subscribers', () async {
    final eventFuture = DomainEventBus.instance
        .on<FileDeletedEvent>()
        .first;

    DomainEventBus.instance.fire(FileDeletedEvent('file-1'));

    expect((await eventFuture).fileId, 'file-1');
  });

  test('typed subscribers ignore unrelated events', () async {
    final received = <FileDeletedEvent>[];
    final subscription = DomainEventBus.instance
        .on<FileDeletedEvent>()
        .listen(received.add);

    DomainEventBus.instance.fire(FolderDeletedEvent('folder-1'));
    DomainEventBus.instance.fire(FileDeletedEvent('file-1'));
    await Future<void>.delayed(Duration.zero);

    expect(received.map((event) => event.fileId), ['file-1']);
    await subscription.cancel();
  });

  test('event bus broadcasts to multiple subscribers', () async {
    final first = DomainEventBus.instance.on<FolderCreatedEvent>().first;
    final second = DomainEventBus.instance.on<FolderCreatedEvent>().first;

    DomainEventBus.instance.fire(FolderCreatedEvent('folder-1', 'Documents'));

    expect((await first).name, 'Documents');
    expect((await second).folderId, 'folder-1');
  });
}
