import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchResults extends StatelessWidget {
  final String? artistName;
  final String? trackName;
  final String? artistUrl;
  final String? trackUrl;
  final String? languageLabel;

  const SearchResults({
    super.key, this.artistName, this.trackName,
    this.artistUrl, this.trackUrl, this.languageLabel
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 設定為白色背景
      appBar: AppBar(
        title: const Text('以前聽過的歌'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black, // 設定 AppBar 文字顏色
        elevation: 0, // 移除陰影更簡潔
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 中間居中的標題
              const Text(
                '以前聽過的歌',
                style: TextStyle(fontSize: 18, color: Colors.black87),
              ),
              const SizedBox(height: 12),

              // 2. 語言類別
              Text(
                languageLabel ?? '國語歌',
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 32),

              // 3. 搜尋結果標籤 (左對齊)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    '搜尋結果',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. 歌曲清單項目
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    // 圖片區域
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.grey[200],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          artistUrl ?? 'http://googleusercontent.com/image_collection/image_retrieval/5495305988097026397',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.person, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // 歌手與歌曲名稱 (使用 Expanded 避免溢出)
                    Expanded(
                      flex: 2,
                      child: Text(
                        artistName ?? '葛蘭',
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        trackName ?? '我要你的愛',
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                    ),

                    // 播放按鈕
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: TextButton(
                        onPressed: () {
                          final params = {
                            'embedUrl': trackUrl,
                          };
                          final uri = Uri(
                            path: '/play_music',
                            queryParameters: params
                          ).toString();
                          context.push(uri);
                        },
                        child: const Text(
                          '播放',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}