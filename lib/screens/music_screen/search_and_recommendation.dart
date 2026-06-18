import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/services/nvidia_llm_service.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:remini_care_ai_app/services/youtube_api_service.dart';

import '../../services/spotify_api_services.dart';

class SearchAndRecommendation extends StatefulWidget {
  final String? languageLabel;

  const SearchAndRecommendation({super.key, this.languageLabel});

  @override
  State<StatefulWidget> createState() => _SearchAndRecommendationState();
}

class _SearchAndRecommendationState extends State<SearchAndRecommendation> {
  // 模擬歌單資料
  final NvidiaLlmService _llmService = NvidiaLlmService();
  final spotifyClientId = ReminiCareConfig.spotifyClientId;
  final spotifyClientSecret = ReminiCareConfig.spotifyClientSecret;
  List<String> recommendationSongsName = [];
  List<Map<String, String>> songs = [];

  bool _isLoading = true;
  Future<void> _loadSongsData() async {
    try {
      recommendationSongsName = await _llmService.recommendationSongsName(widget.languageLabel);

      for (String name in recommendationSongsName) {
        await _getEmbedUrls(name);
      }

    } catch (e) {
      print("抓取歌曲資料發生錯誤: $e");
    } finally {
      // 資料全部抓完後，更新畫面
      // 確保畫面還沒被關閉才 setState，防止之前遇過的 dispose 錯誤
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getEmbedUrls(String query) async {
    // final spotifyApiServices = SpotifyApiServices(
    //     spotifyClientId,
    //     spotifyClientSecret
    // );
    final api = YoutubeApiServices();
    final List<String>? spotifySearchResults = await api.getArtistAndTracks(query) as List<String>?;

    if (spotifySearchResults != null && spotifySearchResults.length >= 4) {
      String artistName = spotifySearchResults[0];
      String trackName = spotifySearchResults[1];
      String artistUrl = spotifySearchResults[2];
      String trackUrl = spotifySearchResults[3];

      songs.add({
        "artistName": artistName,
        "artistUrl": artistUrl,
        "trackName": trackName,
        "trackUrl": "$trackUrl",
      });
      print("成功加入: $trackName");
    }
  }

  @override 
  void initState() {
    super.initState();
    _loadSongsData();
  }
  
  @override
  Widget build(BuildContext context) {
    String? languageLabel = widget.languageLabel;
    return Scaffold(
      appBar: AppBar(title: Text('搜尋歌曲')),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Center(
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
                    style: const TextStyle(fontSize: 45, fontWeight: FontWeight.w500),
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
                          height: 50,
                          child: Stack(
                            alignment: Alignment.center,
                            children: const [
                              Text(
                                '點擊搜尋',
                                style: TextStyle(fontSize: 40, color: Colors.black87),
                              ),
                              Positioned(
                                right: 8,
                                child: Icon(Icons.search, size: 40, color: Colors.black),
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
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
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
                          child: const Text('歌手名字', style: TextStyle(fontSize: 30)),
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
                          child: const Text('歌名', style: TextStyle(fontSize: 30)),
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
                    primary: true,
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                        child: Row(
                          children: [
                            // 專輯封面 (此處使用灰色方塊作為佔位，實作時可換成 Image.asset 或 Image.network)
                            Container(
                              width: 100,
                              height: 100,
                              color: Colors.grey[300],
                              child: (song['artistUrl'] != null && song['artistUrl']!.isNotEmpty)
                                  ? Image.network(
                                    song['artistUrl']!,
                                    fit: BoxFit.cover,
                                  )
                                  : Container(
                                    color: Colors.grey[200], // 給一個淡灰色的底
                                    child: const Icon(
                                    Icons.person, // 也可以換成 Icons.music_note
                                    size: 40,
                                    color: Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // 歌手名稱
                            Expanded(
                              flex: 2,
                              child: Text(
                                song['artistName']!,
                                style: const TextStyle(fontSize: 30),
                              ),
                            ),

                            // 歌曲名稱
                            Expanded(
                              flex: 3,
                              child: Text(
                                song['trackName']!,
                                style: const TextStyle(fontSize: 30),
                              ),
                            ),

                            // 播放按鈕
                            InkWell(
                              onTap: () {
                                final params = {
                                  'embedUrl': song['trackUrl'],
                                };
                                final uri = Uri(
                                    path: '/play_music',
                                    queryParameters: params
                                ).toString();
                                context.push(uri);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('播放', style: TextStyle(fontSize: 30)),
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