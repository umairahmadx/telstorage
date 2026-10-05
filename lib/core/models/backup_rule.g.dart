// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_rule.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BackupRuleAdapter extends TypeAdapter<BackupRule> {
  @override
  final int typeId = 4;

  @override
  BackupRule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BackupRule(
      id: fields[0] as String,
      albumName: fields[1] as String,
      enabled: fields[2] as bool,
      includePhotos: fields[3] as bool,
      includeVideos: fields[4] as bool,
      wifiOnly: fields[5] as bool,
      chargingOnly: fields[6] as bool,
      windowStartMinutes: fields[7] as int,
      windowEndMinutes: fields[8] as int,
      backfillDone: fields[9] as bool,
      backupFolderId: fields[10] as String?,
      albumFolderId: fields[11] as String?,
      retentionKeepLast: fields[12] as int,
      lastRunAt: fields[13] as DateTime?,
      lastResult: fields[14] as String?,
      lastUploadedCount: fields[15] as int,
      createdAt: fields[16] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, BackupRule obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.albumName)
      ..writeByte(2)
      ..write(obj.enabled)
      ..writeByte(3)
      ..write(obj.includePhotos)
      ..writeByte(4)
      ..write(obj.includeVideos)
      ..writeByte(5)
      ..write(obj.wifiOnly)
      ..writeByte(6)
      ..write(obj.chargingOnly)
      ..writeByte(7)
      ..write(obj.windowStartMinutes)
      ..writeByte(8)
      ..write(obj.windowEndMinutes)
      ..writeByte(9)
      ..write(obj.backfillDone)
      ..writeByte(10)
      ..write(obj.backupFolderId)
      ..writeByte(11)
      ..write(obj.albumFolderId)
      ..writeByte(12)
      ..write(obj.retentionKeepLast)
      ..writeByte(13)
      ..write(obj.lastRunAt)
      ..writeByte(14)
      ..write(obj.lastResult)
      ..writeByte(15)
      ..write(obj.lastUploadedCount)
      ..writeByte(16)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupRuleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
