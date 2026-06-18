import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class PlayMusic extends StatefulWidget {
  final String embedUrl;
  const PlayMusic({super.key, required this.embedUrl});

  @override
  State<StatefulWidget> createState() => _PlayMusicState();
}

class _PlayMusicState extends State<PlayMusic> {
  late YoutubePlayerController _controller;
  String _selectedLanguage = '中文';

  @override
  void initState() {
    super.initState();
    String? videoId = YoutubePlayerController.convertUrlToId(widget.embedUrl);
    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId ?? '',
      params: const YoutubePlayerParams(showControls: true, showFullscreenButton: true),
    );
  }

  // 建立左側語言切換按鈕
  Widget _buildLanguageToggle(String label) {
    bool isSelected = _selectedLanguage == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedLanguage = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFDE065) : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : Colors.black54,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 💡 鎖定播放器高度為螢幕的 40%
    final double playerHeight = MediaQuery.of(context).size.height * 0.6;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        // 💡 限制整體的最大寬度，避免在電腦螢幕上拉得太開
        child: Container(
          width: MediaQuery.of(context).size.width * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 1. 播放器區域
              SizedBox(
                height: playerHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: YoutubePlayer(controller: _controller),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2. 一體化卡片區域 (包含語言切換 + 問答)
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10)],
                  ),
                  child: Column(
                    children: [
                      // 💡 語言按鈕置中，與問題區完美對齊
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLanguageToggle('台語'),
                          const SizedBox(width: 16),
                          _buildLanguageToggle('中文'),
                        ],
                      ),
                      const Divider(height: 40),

                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            // 💡 關鍵修改：將 Column 包進 SingleChildScrollView
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text("第一次聽到這首歌是什麼時候？", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  const Text("幾歲的時候？在哪裡聽到？當時跟誰一起？", style: TextStyle(fontSize: 16, color: Colors.grey)),
                                  const SizedBox(height: 20),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFDE065)),
                                    child: const Text("想換歌", style: TextStyle(color: Colors.black)),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

}