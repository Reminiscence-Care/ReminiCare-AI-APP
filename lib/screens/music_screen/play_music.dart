import 'dart:math';
import 'package:flutter/material.dart';
import 'package:remini_care_ai_app/screens/question_generator.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:remini_care_ai_app/services/audio_services/voice_assistant_services.dart';

class PlayMusic extends StatefulWidget {
  final String embedUrl;
  const PlayMusic({super.key, required this.embedUrl});

  @override
  State<StatefulWidget> createState() => _PlayMusicState();
}

class _PlayMusicState extends State<PlayMusic> {
  late YoutubePlayerController _controller;
  String _selectedLanguage = '中文';
  final VoiceAssistantManager _voiceAssistantManager = VoiceAssistantManager();
  late final List<String> questionAndSubQuestion = TopicQuestionGenerator.generateMusicQuestion();
  String _questionText = "";
  bool _isPlayingSequence = false;

  @override
  void initState() {
    super.initState();

    _init();
  }

  Future<void> _init() async {
    String? videoId =
    YoutubePlayerController.convertUrlToId(widget.embedUrl);

    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId ?? '',
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true ,
      ),
    );

    _questionText = questionAndSubQuestion.join(', ');

    _voiceAssistantManager.onPlayingLanguageChanged =
        (language) {
      if (mounted) {
        setState(() {
          _selectedLanguage = language;
        });
      }
    };

    _isPlayingSequence = true;

    await _voiceAssistantManager.playLanguageSequence(
      texts: [_questionText],
      languages: ["台語", "中文"],
      repeatCount: 1,
    );

    _isPlayingSequence = false;
  }

  // 建立左側語言切換按鈕
  Widget _buildLanguageToggle(String label) {
    bool isSelected = _selectedLanguage == label;
    return GestureDetector(
      onTap: () async {
        await _voiceAssistantManager.stopCurrentPlayback();

        if (!mounted) return;

        setState(() {
          _selectedLanguage = label;
        });

        await _voiceAssistantManager.playLanguageSequence(
          texts: [_questionText],
          languages: [label],
          repeatCount: 1,
        );
      },
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
  void dispose() {
    _voiceAssistantManager.stopCurrentPlayback();
    _controller.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double playerHeight = MediaQuery.of(context).size.height * 0.5;

    return YoutubePlayerControllerProvider(
        controller: _controller,
        child: Scaffold(
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
                          child: YoutubePlayer(
                              controller: _controller,
                              autoFullScreen: false,
                              enableFullScreenOnVerticalDrag: false,
                          ),
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
                          // 💡 關鍵修改：將 Row 改為 Wrap
                          Wrap(
                            alignment: WrapAlignment.center, // 置中對齊
                            crossAxisAlignment: WrapCrossAlignment.center, // 垂直置中對齊
                            spacing: 16.0, // 按鈕之間的水平間距 (取代原有的 SizedBox)
                            runSpacing: 16.0, // 當空間不足自動換行時，上下兩行的垂直間距
                            children: [
                              _buildLanguageToggle('台語'),
                              _buildLanguageToggle('中文'),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFDE065),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                child: const Text(
                                  "想換歌",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 30, // 保持大字體，Wrap 會自動處理空間
                                  ),
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Divider(height: 1), // 將 Divider 簡化，避免高度干擾
                          const SizedBox(height: 20),

                          Text(
                            questionAndSubQuestion[0],
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            questionAndSubQuestion[1],
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        )
    );
  }
}