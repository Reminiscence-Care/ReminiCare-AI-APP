import 'dart:math';
import 'package:flutter/material.dart';
import 'package:remini_care_ai_app/screens/music_screen/question_generate.dart';
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
  final question = QuestionGenerate();
  late final List<String> questionAndSubQuestion = question.questionAndSubQuestionGenerate();

  @override
  void initState() {
    super.initState();
    String? videoId = YoutubePlayerController.convertUrlToId(widget.embedUrl);
    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId ?? '',
      params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
      ),
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
    final double playerHeight = MediaQuery.of(context).size.height * 0.6;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
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

                // 2. 一體化卡片區域
                // 不再用 Expanded，改用固定高度或動態高度，防止溢出
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // 讓容器根據內容自動適應高度
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLanguageToggle('台語'),
                          const SizedBox(width: 16),
                          _buildLanguageToggle('中文'),
                        ],
                      ),
                      const Divider(height: 40),

                      Text(questionAndSubQuestion[0],
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(questionAndSubQuestion[1],
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFDE065)),
                        child: const Text("想換歌", style: TextStyle(color: Colors.black)),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}