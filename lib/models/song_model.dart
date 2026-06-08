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

  @HiveField(4)
  String language;

  @HiveField(5)
  int year;

  SongModel({
    required this.singer,
    required this.title,
    required this.imagePath,
    required this.audioPath,
    required this.language,
    required this.year,
  });
}