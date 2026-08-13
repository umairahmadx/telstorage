import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/file_record.dart';

/// Base class for all domain events.
/// Sealed so all subtypes are defined in this file for exhaustive switching.
@immutable
sealed class DomainEvent {
  final DateTime timestamp;
  DomainEvent() : timestamp = DateTime.now();
}

// ── File Lifecycle Events ─────────────────────────────────────────────────────

class FileUploadedEvent extends DomainEvent {
  final FileRecord file;
  FileUploadedEvent(this.file);
}

class FileDeletedEvent extends DomainEvent {
  final String fileId;
  FileDeletedEvent(this.fileId);
}

class FileRenamedEvent extends DomainEvent {
  final String fileId;
  final String newName;
  FileRenamedEvent(this.fileId, this.newName);
}

class FileCopiedEvent extends DomainEvent {
  final String originalFileId;
  final String newFileId;
  FileCopiedEvent(this.originalFileId, this.newFileId);
}

// ── Folder Lifecycle Events ───────────────────────────────────────────────────

class FolderCreatedEvent extends DomainEvent {
  final String folderId;
  final String name;
  FolderCreatedEvent(this.folderId, this.name);
}

class FolderDeletedEvent extends DomainEvent {
  final String folderId;
  FolderDeletedEvent(this.folderId);
}

class FolderRenamedEvent extends DomainEvent {
  final String folderId;
  final String newName;
  FolderRenamedEvent(this.folderId, this.newName);
}

// ── Web Share Events ──────────────────────────────────────────────────────────

class WebShareCompletedEvent extends DomainEvent {
  final String fileId;
  final String shareUrl;
  WebShareCompletedEvent(this.fileId, this.shareUrl);
}

// ── Sync Events ───────────────────────────────────────────────────────────────

class SyncCompletedEvent extends DomainEvent {
  final int filesAdded;
  final int filesRemoved;
  SyncCompletedEvent({this.filesAdded = 0, this.filesRemoved = 0});
}

/// Decoupled event bus for cross-feature reactivity.
///
/// Any service can fire events without knowing which features listen.
/// Any BLoC/Cubit can subscribe to typed events without importing services.
///
/// This replaces tight coupling between Upload ↔ Browser ↔ Home with a
/// single broadcast channel in the domain layer.
class DomainEventBus {
  static final DomainEventBus instance = DomainEventBus._();
  DomainEventBus._();

  final _controller = StreamController<DomainEvent>.broadcast();

  /// Full untyped stream — useful for logging or catch-all listeners.
  Stream<DomainEvent> get stream => _controller.stream;

  /// Type-filtered stream — subscribe to only one event type.
  Stream<T> on<T extends DomainEvent>() {
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  /// Fire an event to all listeners.
  void fire(DomainEvent event) {
    _controller.add(event);
  }
}
