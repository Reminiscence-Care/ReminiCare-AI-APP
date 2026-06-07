import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    // 根據傳入的年代與語言，模擬對應的歌單資料
    final List<Map<String, String>> songs = [
      {'singer': '周璇', 'song': '夜上海', 'image': 'assets/images/zhouxuan.png'},
      {'singer': '葛蘭', 'song': '我要你的愛', 'image': 'assets/images/gelan.png'},
      {'singer': '靜婷', 'song': '明日之歌', 'image': 'assets/images/jingting.png'},
    ];

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
                  const SizedBox(width: 60), // 對齊大頭照寬度
                  Expanded(child: Center(child: _buildHeaderTag('歌手名字'))),
                  Expanded(child: Center(child: _buildHeaderTag('歌名'))),
                  const SizedBox(width: 80), // 對齊按鈕寬度
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 歌單列表
            Expanded(
              child: ListView.separated(
                itemCount: songs.length,
                separatorBuilder: (context, index) => const Divider(height: 24, color: Color(0xFFE0E0E0)),
                itemBuilder: (context, index) {
                  final item = songs[index];
                  return Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          item['image']!, width: 60, height: 60, fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(width: 60, height: 60, color: Colors.grey[300], child: const Icon(Icons.person, color: Colors.white)),
                        ),
                      ),
                      Expanded(child: Center(child: Text(item['singer']!, style: const TextStyle(fontSize: 20)))),
                      Expanded(child: Center(child: Text(item['song']!, style: const TextStyle(fontSize: 20)))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE0E0E0),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          // 💡 點擊後將選中的歌曲細節與分類打包，推入獨立播放頁面
                          context.push('/play_music_screen', extra: {
                            'singer': item['singer']!,
                            'song': item['song']!,
                            'image': item['image']!,
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