import 'package:hive/hive.dart';

part 'song_model.g.dart';

@HiveType(typeId: 0)
class SongModel extends HiveObject {
  @HiveField(0)
  String singer;

  @HiveField(1)
  String title;

  @HiveField(2)
  String imagePath;

  @HiveField(3)
  String audioPath;

  SongModel({
    required this.singer,
    required this.title,
    required this.imagePath,
    required this.audioPath,
  });
}