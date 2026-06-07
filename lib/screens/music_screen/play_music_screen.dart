import 'package:flutter/material.dart';

class PlayMusicScreen extends StatelessWidget {
  final Map<String, dynamic> songData;

  const PlayMusicScreen({super.key, required this.songData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7EE), // 溫暖的米色背景 (對應你的設計圖)
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.brown),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- 頂部標籤 ---
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTag(songData['year']),
                const SizedBox(width: 12),
                _buildTag(songData['language']),
              ],
            ),
            const SizedBox(height: 30),

            // --- 歌名與歌手圖片區域 ---
            Text(
              songData['song'],
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 6),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  songData['image'],
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(width: 200, height: 200, color: Colors.grey[300], child: const Icon(Icons.person, size: 80, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              songData['singer'],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 30),

            // --- 播放控制列 ---
            Row(
              children: [
                // 播放按鈕
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFB06A41), // 復古棕紅色
                  ),
                  child: IconButton(
                    iconSize: 40,
                    color: Colors.white,
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      // 這裡未來可以放入 just_audio 的播放邏輯
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // 進度條
                Expanded(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: 0.3, // 假定進度
                          minHeight: 12,
                          backgroundColor: Colors.brown[100],
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD7CCC8)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('00:46', style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
                          Text('02:46', style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // --- 歌詞顯示區 ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.brown[200]!),
              ),
              child: const Text(
                '點播放後，這裡會出現目前唱\n到的歌詞',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, color: Colors.brown, fontWeight: FontWeight.bold, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),

            // --- 互動問句 ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFDEBCE),
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: Colors.brown[700]!, width: 6)),
              ),
              child: const Text(
                '這首歌你有聽過嗎？',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // 輔助函式：建立圓角標籤 (例如 "1950-1960年代")
  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF8D5524), // 深棕色
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}