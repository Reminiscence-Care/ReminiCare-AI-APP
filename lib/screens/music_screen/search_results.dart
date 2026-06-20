import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchResults extends StatelessWidget {
  final String? languageLabel;
  final String? songsDataJson;

  const SearchResults({
    super.key,
    this.languageLabel,
    this.songsDataJson,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;

    List<Map<String, String>> songsList = [];
    if (songsDataJson != null && songsDataJson!.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(songsDataJson!);
        songsList = decoded.map((e) => Map<String, String>.from(e)).toList();
      } catch (e) {
        debugPrint("解析歌曲資料失敗: $e");
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 40),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // ================= 上半部：白色區域 (維持不變) =================
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: size.height * 0.02),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '以前聽過的歌',
                    style: TextStyle(
                      fontSize: (screenWidth * 0.06).clamp(20.0, 24.0),
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF59D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    languageLabel ?? '國語歌',
                    style: TextStyle(
                      fontSize: (screenWidth * 0.06).clamp(20.0, 24.0),
                      color: Colors.black87,
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.05),
              ],
            ),
          ),

          // ================= 下半部：灰色區域 =================
          Expanded( // 💡 這個外層的 Expanded 負責撐滿下半部螢幕
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF5F5F5),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 3. 搜尋結果標籤 (固定不滑動)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '結果',
                      style: TextStyle(
                        fontSize: (screenWidth * 0.05).clamp(18.0, 22.0),
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 4. 動態歌曲清單 (使用 ListView.builder)
                  Expanded(
                    child: songsList.isEmpty
                        ? Center(
                      child: Text(
                        "沒有找到相關歌曲",
                        style: TextStyle(
                          fontSize: (screenWidth * 0.05).clamp(18.0, 22.0),
                          color: Colors.grey,
                        ),
                      ),
                    )
                        : ListView.builder(
                      itemCount: songsList.length,
                      // 加上 padding 避免最後一首歌貼齊螢幕底部
                      padding: const EdgeInsets.only(bottom: 40.0),
                      itemBuilder: (context, index) {
                        final song = songsList[index];
                        return _buildSongRow(context, song, screenWidth);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 單一歌曲的 UI 元件
  Widget _buildSongRow(BuildContext context, Map<String, String> song, double screenWidth) {
    final String artistUrl = song['artistUrl'] ?? '';
    final String artistName = song['artistName'] ?? '未知歌手';
    final String trackName = song['trackName'] ?? '未知歌曲';
    final String trackUrl = song['trackUrl'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          Container(
            width: (screenWidth * 0.2).clamp(80.0, 100.0),
            height: (screenWidth * 0.2).clamp(80.0, 100.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[300],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                artistUrl.isNotEmpty ? artistUrl : 'https://via.placeholder.com/150',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.music_note, color: Colors.grey, size: 40),
              ),
            ),
          ),
          const SizedBox(width: 16),

          Expanded(
            flex: 2,
            child: Text(
              artistName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (screenWidth * 0.05).clamp(18.0, 22.0),
                color: Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              trackName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (screenWidth * 0.05).clamp(18.0, 22.0),
                color: Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),

          InkWell(
            onTap: () {
              if (trackUrl.isEmpty) return;

              final params = {'embedUrl': trackUrl};
              final uri = Uri(
                path: '/play_music',
                queryParameters: params,
              ).toString();
              context.push(uri);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDE065),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '聽歌',
                style: TextStyle(
                  fontSize: (screenWidth * 0.045).clamp(16.0, 20.0),
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}