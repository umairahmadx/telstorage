// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_ledger_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BackupLedgerEntryAdapter extends TypeAdapter<BackupLedgerEntry> {
  @override
  final int typeId = 5;

  @override
  BackupLedgerEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BackupLedgerEntry(
      assetId: fields[0] as String,
      fingerprint: fields[1] as String,
      lastKnownPath: fields[2] as String?,
      destFileId: fields[3] as String?,
      destFolderId: fields[4] as String?,
      uploadedAt: fields[5] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, BackupLedgerEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.assetId)
      ..writeByte(1)
      ..write(obj.fingerprint)
      ..writeByte(2)
      ..write(obj.lastKnownPath)
      ..writeByte(3)
      ..write(obj.destFileId)
      ..writeByte(4)
      ..write(obj.destFolderId)
      ..writeByte(5)
      ..write(obj.uploadedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupLedgerEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
