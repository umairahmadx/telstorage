/*
 * File: folder_record.dart
 * Description: Component and logic definition for folder_record.dart in TelStorage.
 */

import 'package:hive/hive.dart';
import 'app_metadata.dart';

part 'folder_record.g.dart';

/// Hive local model for cached folder metadata
@HiveType(typeId: 1)
class FolderRecord extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? parentId;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4)
  int itemCount;

  FolderRecord({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    this.itemCount = 0,
  });

  factory FolderRecord.fromFolder(Folder folder) {
    return FolderRecord(
      id: folder.id,
      name: folder.name,
      parentId: folder.parentId,
      createdAt: folder.createdAt,
      itemCount: folder.itemCount,
    );
  }

  Folder toFolder() {
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: createdAt,
      itemCount: itemCount,
    );
  }
}
