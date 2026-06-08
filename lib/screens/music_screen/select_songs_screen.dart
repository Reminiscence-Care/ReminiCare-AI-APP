import 'dart:io'; // 💡 必須引入 dart:io 才能使用 File() 讀取本機圖片
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:remini_care_ai_app/models/song_model.dart';

class SelectSongsScreen extends StatelessWidget {
  final String musicLanguage;
  final String yearLabel;
  const SelectSongsScreen({
    super.key,
    required this.musicLanguage,
    required this.yearLabel,
  });

  @override
  Widget build(BuildContext context) {
    // 解析年份範圍 (例如 yearLabel 傳入 "1960"，範圍就是 1960 ~ 1969)
    // 💡 建議：因為 yearLabel 原本是 "1950-1960" 這種格式，如果你前面已經改成單一數字傳遞，
    // 這裡的 tryParse 才能成功。如果 yearLabel 還是 "1950-1960"，你要用 substring 切割喔！
    // 這裡先依照你的寫法：假設 yearLabel 傳進來是乾淨的年份字串，如 "1960"
    final int yearLowerBound = int.tryParse(yearLabel.substring(0, 4)) ?? 1950; // 加個安全預設值
    final int yearUpperBound = yearLowerBound + 10;

    // 從資料庫撈取並過濾出符合年代與語言的歌曲
    var box = Hive.box<SongModel>('my_music_box');
    List<SongModel> filteredSongs = box.values.where((song){
      return (song.language == musicLanguage) && (song.year >= yearLowerBound && song.year < yearUpperBound);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('$yearLabel  $musicLanguage'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // 頂部欄位對齊標籤
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  const SizedBox(width: 60),
                  Expanded(child: Center(child: _buildHeaderTag('歌手名字'))),
                  Expanded(child: Center(child: _buildHeaderTag('歌名'))),
                  const SizedBox(width: 80),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 歌單列表區塊
            Expanded(
              // 💡 貼心防呆：如果資料庫裡剛好這個分類沒有歌，顯示提示文字
              child: filteredSongs.isEmpty
                  ? const Center(
                child: Text(
                  '這個分類目前還沒有歌曲喔，趕快去新增吧！',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              )
                  : ListView.separated(
                itemCount: filteredSongs.length, // 👈 改用動態長度
                separatorBuilder: (context, index) => const Divider(height: 24, color: Color(0xFFE0E0E0)),
                itemBuilder: (context, index) {
                  final song = filteredSongs[index]; // 👈 拿出 SongModel 物件

                  return Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        // 💡 關鍵修改：從 Image.asset 改成 Image.file，因為路徑是本機真實路徑
                        child: Image.file(
                          File(song.imagePath),
                          width: 60, height: 60, fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(width: 60, height: 60, color: Colors.grey[300], child: const Icon(Icons.person, color: Colors.white)),
                        ),
                      ),
                      Expanded(child: Center(child: Text(song.singer, style: const TextStyle(fontSize: 20)))), // 👈 song.singer
                      Expanded(child: Center(child: Text(song.title, style: const TextStyle(fontSize: 20)))),  // 👈 song.title
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE0E0E0),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          // 💡 將真實的資料打包傳給播放頁面
                          context.push('/play_music_screen', extra: {
                            'singer': song.singer,
                            'song': song.title,
                            'image': song.imagePath, // 本機路徑
                            'audioPath': song.audioPath, // 👈 順便把音樂檔案路徑也傳過去！
                            'year': yearLabel,
                            'language': musicLanguage,
                          });
                        },
                        child: const Text('播放', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
    );
  }
}