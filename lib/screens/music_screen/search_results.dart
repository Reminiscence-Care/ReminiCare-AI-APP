import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchResults extends StatelessWidget {
  final String? artistName;
  final String? trackName;
  final String? artistUrl;
  final String? trackUrl;
  final String? languageLabel;

  const SearchResults({
    super.key,
    this.artistName,
    this.trackName,
    this.artistUrl,
    this.trackUrl,
    this.languageLabel,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;

    return Scaffold(
      backgroundColor: Colors.white, // 上半部維持純白背景
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
          // ================= 上半部：白色區域 =================
          SizedBox(
            width: double.infinity, // 強迫撐滿寬度，讓子元件完美置中
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: size.height * 0.02),

                // 1. 灰色標籤：以前聽過的歌
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

                // 2. 淺黃色標籤：國語歌
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
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF5F5F5),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 讓結果標籤靠左
                  children: [
                    // 3. 搜尋結果標籤 (左對齊)
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

                    // 4. 歌曲清單項目
                    Row(
                      children: [
                        // 圖片區域 (動態縮放)
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
                              artistUrl ?? 'http://googleusercontent.com/image_collection/image_retrieval/5495305988097026397',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.person, color: Colors.grey, size: 40),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // 歌手名稱 (使用 Expanded 平分空間，並置中對齊)
                        Expanded(
                          flex: 2,
                          child: Text(
                            artistName ?? '葛蘭',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: (screenWidth * 0.05).clamp(18.0, 22.0),
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // 歌曲名稱
                        Expanded(
                          flex: 3,
                          child: Text(
                            trackName ?? '我要你的愛',
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
                            final safeTrackUrl = trackUrl ?? '';
                            final params = {'embedUrl': safeTrackUrl};
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}