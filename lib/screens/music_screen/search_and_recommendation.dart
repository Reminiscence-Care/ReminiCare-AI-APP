import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/services/nvidia_llm_service.dart';
import 'package:remini_care_ai_app/services/music_services/youtube_api_service.dart';

class SearchAndRecommendation extends StatefulWidget {
  final String? languageLabel;

  const SearchAndRecommendation({super.key, this.languageLabel});

  @override
  State<StatefulWidget> createState() => _SearchAndRecommendationState();
}

class _SearchAndRecommendationState extends State<SearchAndRecommendation> {
  final NvidiaLlmService _llmService = NvidiaLlmService();
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getEmbedUrls(String query) async {
    final api = YoutubeApiServices();
    final List<String>? searchResults = await api.getArtistAndTracks(query);

    if (searchResults != null && searchResults.length >= 4) {
      String artistName = searchResults[0];
      String trackName = searchResults[1];
      String artistUrl = searchResults[2];
      String trackUrl = searchResults[3];

      songs.add({
        "artistName": artistName,
        "artistUrl": artistUrl,
        "trackName": trackName,
        "trackUrl": trackUrl,
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
    String? languageLabel = widget.languageLabel ?? '國語歌';
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea( // 確保不會被手機頂部瀏海擋住
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFDE065)))
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Row(
                children: [
                  // 返回按鈕
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black, size: 40),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 16),

                  // 黃色搜尋框
                  Expanded(
                    child: InkWell(
                      onTap: () => context.push('/search_options/$languageLabel'),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDE065), // 鮮黃色
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center, // 讓「搜尋」兩字置中
                          children: const [
                            Expanded(
                              child: Text(
                                '搜尋',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 22, color: Colors.black87),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(right: 16.0),
                              child: Icon(Icons.search, size: 30, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. 中間灰色分類標題列
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              color: Colors.grey[300], // 灰色橫條背景
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 靠左的語言標籤
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      languageLabel,
                      style: const TextStyle(fontSize: 24, color: Colors.black87),
                    ),
                  ),
                  // 絕對置中的推薦歌單
                  const Text(
                    '推薦歌單',
                    style: TextStyle(fontSize: 24, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. 列表標題
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  const SizedBox(width: 80), // 預留給圖片的寬度
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF59D), // 淺黃色
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('歌手名字', style: TextStyle(fontSize: 18, color: Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF59D), // 淺黃色
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('歌名', style: TextStyle(fontSize: 18, color: Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 80), // 預留給右邊聽歌按鈕的寬度
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. 歌曲列表清單
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                thickness: 6.0,
                radius: const Radius.circular(8),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  itemCount: songs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16), // 每個 item 之間的間距
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return Row(
                      children: [
                        // 專輯封面縮小至 80x80，適應多數手機
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (song['artistUrl'] != null && song['artistUrl']!.isNotEmpty)
                              ? Image.network(
                            song['artistUrl']!,
                            fit: BoxFit.cover,
                          )
                              : const Icon(Icons.person, size: 32, color: Colors.grey),
                        ),
                        const SizedBox(width: 16),

                        // 歌手名稱
                        Expanded(
                          flex: 2,
                          child: Text(
                            song['artistName'] ?? '未知歌手',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, color: Colors.black87),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // 歌曲名稱
                        Expanded(
                          flex: 3,
                          child: Text(
                            song['trackName'] ?? '未知歌曲',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, color: Colors.black87),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 16),

                        InkWell(
                          onTap: () {
                            final params = {'embedUrl': song['trackUrl'] ?? ''};
                            final uri = Uri(path: '/play_music', queryParameters: params).toString();
                            context.push(uri);
                          },
                          child: Container(
                            width: 80, // 固定寬度，確保所有按鈕對齊
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDE065), // 鮮黃色
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('聽歌', style: TextStyle(fontSize: 18, color: Colors.black87)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}