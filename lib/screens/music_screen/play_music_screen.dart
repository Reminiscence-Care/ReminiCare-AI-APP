import 'package:flutter/material.dart';

class PlayMusicScreen extends StatelessWidget {
  final Map<String, String> songData; // 接收上一頁傳來的所有歌曲詳情

  const PlayMusicScreen({super.key, required this.songData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2EBE1), // 圖中的淡米色背景
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('正在播放', style: TextStyle(color: Color(0xFF4E342E))),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF4E342E)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
          child: IntrinsicHeight(
            // 確保左右兩張卡片能維持相同的高度
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // 🌟 左側卡片：歌手與照片資訊
                Container(
                  width: 280, // 固定左側卡片寬度
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF9),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 年代標籤 (深棕底白字)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFF7A4A35), borderRadius: BorderRadius.circular(20)),
                        child: Text('${songData['year']}年代', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(height: 12),
                      // 語言文字 (棕字)
                      Text(songData['language']!, style: const TextStyle(color: Color(0xFF7A4A35), fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 28),
                      // 歌手大頭照相框
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 6))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            songData['image']!, width: 180, height: 180, fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(width: 180, height: 180, color: Colors.grey[300], child: const Icon(Icons.person, size: 60, color: Colors.white)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 歌手名字
                      Text(songData['singer']!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4E342E))),
                    ],
                  ),
                ),

                const SizedBox(width: 24), // 兩張大卡片的中間空隙

                // 🌟 右側卡片：播放功能與歌詞控制
                Container(
                  width: 440, // 固定右側卡片寬度
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF9),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 歌名
                      Text(songData['song']!, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF4E342E))),
                      const SizedBox(height: 16),

                      // 播放控制與進度條
                      Row(
                        children: [
                          Container(
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFAD5C35)),
                            child: IconButton(
                              iconSize: 40,
                              color: Colors.white,
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () {},
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: 0.0, // 初始進度 00:00
                                    minHeight: 12,
                                    backgroundColor: const Color(0xFFEADFC8),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFAD5C35)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('00:00', style: TextStyle(color: Color(0xFF4E342E), fontWeight: FontWeight.bold)),
                                    Text('02:46', style: TextStyle(color: Color(0xFF4E342E), fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 歌詞區域 (細邊框)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEADFC8), width: 2),
                        ),
                        child: const Text(
                          '點播播放後，這裡會出現目前唱\n到的歌詞',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 22, color: Color(0xFF4E342E), fontWeight: FontWeight.bold, height: 1.6),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 側邊粗線提示框
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCECD9),
                          borderRadius: BorderRadius.circular(12),
                          border: const Border(left: BorderSide(color: Color(0xFFAD5C35), width: 8)),
                        ),
                        child: const Text(
                          '這首歌你有聽過嗎？',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4E342E)),
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}