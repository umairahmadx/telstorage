// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FolderRecordAdapter extends TypeAdapter<FolderRecord> {
  @override
  final int typeId = 1;

  @override
  FolderRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FolderRecord(
      id: fields[0] as String,
      name: fields[1] as String,
      parentId: fields[2] as String?,
      createdAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, FolderRecord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.parentId)
      ..writeByte(3)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
