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

  FolderRecord({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  factory FolderRecord.fromFolder(Folder folder) {
    return FolderRecord(
      id: folder.id,
      name: folder.name,
      parentId: folder.parentId,
      createdAt: folder.createdAt,
    );
  }

  Folder toFolder() {
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: createdAt,
    );
  }
}
