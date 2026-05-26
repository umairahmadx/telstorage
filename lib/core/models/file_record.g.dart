// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FileRecordAdapter extends TypeAdapter<FileRecord> {
  @override
  final int typeId = 0;

  @override
  FileRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FileRecord(
      fileId: fields[0] as String,
      name: fields[1] as String,
      folderId: fields[2] as String?,
      metadataMessageId: fields[3] as int,
      sizeMb: fields[4] as double,
      mimeType: fields[5] as String,
      uploadedAt: fields[6] as DateTime,
      chunkCount: fields[7] as int,
      sha256Hash: fields[8] as String,
      metadataFileId: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FileRecord obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.fileId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.folderId)
      ..writeByte(3)
      ..write(obj.metadataMessageId)
      ..writeByte(4)
      ..write(obj.sizeMb)
      ..writeByte(5)
      ..write(obj.mimeType)
      ..writeByte(6)
      ..write(obj.uploadedAt)
      ..writeByte(7)
      ..write(obj.chunkCount)
      ..writeByte(8)
      ..write(obj.sha256Hash)
      ..writeByte(9)
      ..write(obj.metadataFileId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
