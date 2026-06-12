// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_job.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadJobAdapter extends TypeAdapter<DownloadJob> {
  @override
  final int typeId = 2;

  @override
  DownloadJob read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadJob(
      fileId: fields[0] as String,
      name: fields[1] as String,
      mimeType: fields[2] as String,
      sizeMb: fields[3] as double,
      progress: fields[4] as double,
      status: fields[5] as String,
      localPath: fields[6] as String?,
      error: fields[7] as String?,
      addedAt: fields[8] as DateTime,
      completedAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadJob obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.fileId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.mimeType)
      ..writeByte(3)
      ..write(obj.sizeMb)
      ..writeByte(4)
      ..write(obj.progress)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.localPath)
      ..writeByte(7)
      ..write(obj.error)
      ..writeByte(8)
      ..write(obj.addedAt)
      ..writeByte(9)
      ..write(obj.completedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadJobAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
