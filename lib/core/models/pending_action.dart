import 'package:hive/hive.dart';

part 'pending_action.g.dart';

@HiveType(typeId: 3)
class PendingAction extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String actionType; // 'createFolder' | 'renameFolder' | 'deleteFolder' | 'renameFile' | 'moveFile' | 'deleteFile'

  @HiveField(2)
  final Map<String, dynamic> payload;

  @HiveField(3)
  final DateTime timestamp;

  PendingAction({
    required this.id,
    required this.actionType,
    required this.payload,
    required this.timestamp,
  });
}
