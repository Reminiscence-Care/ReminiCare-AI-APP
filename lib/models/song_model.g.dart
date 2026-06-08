// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SongModelAdapter extends TypeAdapter<SongModel> {
  @override
  final int typeId = 0;

  @override
  SongModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SongModel(
      singer: fields[0] as String,
      title: fields[1] as String,
      imagePath: fields[2] as String,
      audioPath: fields[3] as String,
      language: fields[4] as String,
      year: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, SongModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.singer)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.imagePath)
      ..writeByte(3)
      ..write(obj.audioPath)
      ..writeByte(4)
      ..write(obj.language)
      ..writeByte(5)
      ..write(obj.year);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
