import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchAndRecommendation extends StatefulWidget {
  final String? languageLabel;

  const SearchAndRecommendation({super.key, this.languageLabel});

  @override
  State<StatefulWidget> createState() => _SearchAndRecommendationState();
}

class _SearchAndRecommendationState extends State<SearchAndRecommendation> {
  // 模擬歌單資料
  final List<Map<String, String>> songs = [
    {
      'artist': '周璇',
      'title': '夜上海',
      'image': 'assets/zhou_xuan.png',
    },
    {
      'artist': '葛蘭',
      'title': '我要你的愛',
      'image': 'assets/grace_chang.png',
    },
    {
      'artist': '靜婷',
      'title': '明日之歌',
      'image': 'assets/tsin_ting.png',
    },
  ];

  @override
  Widget build(BuildContext context) {
    String? languageLabel = widget.languageLabel;
    return Scaffold(
      appBar: AppBar(title: Text('搜尋歌曲')),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(16.0),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 頂部搜尋列
              Row(
                children: [
                  Text(
                    widget.languageLabel ?? '國語歌',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Material(
                      color: Colors.grey[300], // 將背景色設定在 Material 上
                      borderRadius: BorderRadius.circular(4.0),
                      child: InkWell(
                        onTap: () {
                          context.push('/search_options/$languageLabel');
                        },
                        borderRadius: BorderRadius.circular(4.0),
                        child: SizedBox(
                          height: 36,
                          child: Stack(
                            alignment: Alignment.center,
                            children: const [
                              Text(
                                '點擊搜尋',
                                style: TextStyle(fontSize: 16, color: Colors.black87),
                              ),
                              Positioned(
                                right: 8,
                                child: Icon(Icons.search, size: 20, color: Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  )
                ],
              ),
              const SizedBox(height: 32),

              // 2. 標題
              const Text(
                '推薦歌單',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 32),

              // 3. 列表標題 (歌手名字 / 歌名)
              Padding(
                padding: const EdgeInsets.only(right: 16.0), // 預留右側捲軸空間
                child: Row(
                  children: [
                    const SizedBox(width: 76), // 圖片寬度 (60) + 間距 (16)
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('歌手名字', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('歌名', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 70), // 「播放」按鈕預留空間
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. 歌曲列表
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  thickness: 6.0,
                  radius: const Radius.circular(8),
                  child: ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                        child: Row(
                          children: [
                            // 專輯封面 (此處使用灰色方塊作為佔位，實作時可換成 Image.asset 或 Image.network)
                            Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey[300],
                              child: const Icon(Icons.music_note, color: Colors.grey),
                            ),
                            const SizedBox(width: 16),

                            // 歌手名稱
                            Expanded(
                              flex: 2,
                              child: Text(
                                song['artist']!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),

                            // 歌曲名稱
                            Expanded(
                              flex: 3,
                              child: Text(
                                song['title']!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),

                            // 播放按鈕
                            InkWell(
                              onTap: () {
                                // 點擊播放邏輯
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('播放', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}