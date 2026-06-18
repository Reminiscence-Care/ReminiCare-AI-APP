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
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    // YouTube 影片的 ID (例如 dQw4w9WgXcQ)
    String? videoId = YoutubePlayerController.convertUrlToId(widget.embedUrl);

    if (videoId == null || videoId.isEmpty) {
      _hasError = true;
      return;
    }

    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: false, // 設為 false 讓使用者自己按播放，可避免 iOS/macOS 阻擋自動播放
      params: const YoutubePlayerParams(
        showControls: true,       // 顯示播放進度條
        showFullscreenButton: true, // 允許全螢幕
        mute: false,
        loop: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  // 錯誤提示畫面
  Widget _buildErrorUI() {
    return Container(
      height: 250,
      width: MediaQuery.of(context).size.width * 0.9,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[400]!, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.grey),
          const SizedBox(height: 15),
          const Text(
            "這似乎不是有效的 YouTube 網址",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 15),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text("返回上一頁"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB95A38),
              foregroundColor: Colors.white,
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('音樂播放', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // 影片播放器區塊
              _hasError
                  ? _buildErrorUI()
                  : ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  // 依照 YouTube 標準 16:9 比例設定高度
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: YoutubePlayer(
                    controller: _controller,
                    backgroundColor: Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // 下方提示文字
              Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(
                    left: BorderSide(
                      color: Color(0xFFB95A38),
                      width: 8.0,
                    ),
                  ),
                ),
                child: const Text(
                  "這首經典歌曲，是否有喚起你的一些回憶呢？",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037),
                    height: 1.5,
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}