import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SelectSongsScreen extends StatelessWidget {
  final String language;
  final String year;

  const SelectSongsScreen({
    super.key,
    required this.language,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    // 模擬的歌曲清單資料
    final List<Map<String, dynamic>> songs = [
      {'singer': '周璇', 'song': '夜上海', 'image': 'assets/images/zhouxuan.png'},
      {'singer': '葛蘭', 'song': '我要你的愛', 'image': 'assets/images/gelan.png'},
      {'singer': '靜婷', 'song': '明日之歌', 'image': 'assets/images/jingting.png'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 淡淡的灰白背景
      appBar: AppBar(
        title: Text('$year  $language'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 標題列 (歌手名字 / 歌名)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  const SizedBox(width: 80), // 預留給圖片的空間
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('歌手名字', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('歌名', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 80), // 預留給按鈕的空間
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 歌曲列表
            Expanded(
              child: ListView.separated(
                itemCount: songs.length,
                separatorBuilder: (context, index) => const Divider(height: 30),
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return Row(
                    children: [
                      // 歌手圖片
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          song['image'],
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(width: 60, height: 60, color: Colors.grey, child: const Icon(Icons.person, color: Colors.white)),
                        ),
                      ),

                      // 歌手名字
                      Expanded(
                        child: Center(
                          child: Text(song['singer'], style: const TextStyle(fontSize: 18)),
                        ),
                      ),

                      // 歌名
                      Expanded(
                        child: Center(
                          child: Text(song['song'], style: const TextStyle(fontSize: 18)),
                        ),
                      ),

                      // 播放按鈕
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[300],
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          // 將這首歌的資料與分類打包，傳給播放頁面
                          final songData = {
                            ...song,
                            'language': language,
                            'year': year,
                          };
                          context.push('/play_music_screen', extra: songData);
                        },
                        child: const Text('播放'),
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
}