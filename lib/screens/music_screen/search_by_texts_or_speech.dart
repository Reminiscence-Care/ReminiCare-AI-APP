import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/music_services/youtube_api_service.dart';
import 'package:remini_care_ai_app/services/speech_services.dart';

class SearchByTextsOrSpeech extends StatefulWidget {
  final String? texts_or_speech;
  final String? languageLabel;
  const SearchByTextsOrSpeech({super.key, this.texts_or_speech, this.languageLabel});

  @override
  State<StatefulWidget> createState() => _SearchByTextsOrSpeechState();
}

class _SearchByTextsOrSpeechState extends State<SearchByTextsOrSpeech> {
  final TextEditingController _textController = TextEditingController();

  String? artistName;
  String? trackName;
  String? artistUrl;
  String? trackUrl;
  String? languageLabel;

  final ISTTService sttService = YatingSpeechService();
  final _voiceManager = VoiceAssistantManager();
  bool _isRecording = false;
  String? speechText;

  @override
  void initState() {
    super.initState();
    _initVoiceAssistant();
    languageLabel = widget.languageLabel;
  }

  void _initVoiceAssistant() {
    _voiceManager.onStartChatFlow = () async {
      await _voiceManager.stopActiveAudioOperations();
      _startRecordingSession();
    };

    _voiceManager.onSpeechCompleted = (mergedWavPath) {
      _processMergedAudio(mergedWavPath);
    };

    _voiceManager.onRestartChatFlow = () async {
      await _voiceManager.stopActiveAudioOperations();
      _startRecordingSession();
    };

    _voiceManager.onEndChatFlow = () async {
      await _voiceManager.stopActiveAudioOperations();
      if (speechText != null && speechText!.isNotEmpty) {
        _navigateToNextPage();
      }
    };

    _voiceManager.startBackgroundWakeWordCycle();
  }

  void _startRecordingSession() {
    setState(() { _isRecording = true; });
    _voiceManager.startChatFlow();
  }

  Future<void> _processMergedAudio(List<String>? paths) async {
    setState(() { _isRecording = false; });
    print("取得無損拼接回憶 WAV 檔 (共 ${paths?.length ?? 0} 段)");

    String fullTranscript = "";

    if (paths != null && paths.isNotEmpty) {
      for (String path in paths) {
        final result = await sttService.transcribe(path);
        try { File(path).deleteSync(); } catch (_) {}

        if (result != null && result.trim().isNotEmpty) {
          fullTranscript += result;
        }
      }
    }

    if (fullTranscript.isNotEmpty) {
      speechText = fullTranscript;
      _textController.text = fullTranscript;
      await _setEmbedUrls(fullTranscript);
      _navigateToNextPage();
    } else {
      _showEmptyWarning();
      _voiceManager.checkCompletedCommands = false;
      _voiceManager.startBackgroundWakeWordCycle();
    }
  }

  void _navigateToNextPage() async {
    final safeArtist = artistName ?? '未知歌手';
    final safeTrack = trackName ?? '未知歌曲';
    final safeLang = languageLabel ?? '國語歌';
    final safeArtistUrl = artistUrl ?? '';
    final safeTrackUrl = trackUrl ?? '';

    final queryParams = {
      'artistName': safeArtist,
      'trackName': safeTrack,
      'languageLabel': safeLang,
      'artistUrl': safeArtistUrl,
      'trackUrl': safeTrackUrl,
    };

    final uri = Uri(
        path: '/search_results',
        queryParameters: queryParams
    ).toString();

    if (mounted) context.push(uri);
  }

  void _showEmptyWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lightbulb_outline, color: Colors.white, size: 28),
            SizedBox(width: 10),
            Text(
              "請先輸入或說出想聽的歌哦！",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFFA726), // 溫和的橘色，不會像紅色那麼有警告感
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.only(bottom: 40, left: 20, right: 20),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  @override
  void dispose() {
    _textController.dispose();
    _voiceManager.dispose();
    super.dispose();
  }

  Future<void> _setEmbedUrls(String query) async {
    final api = YoutubeApiServices();
    final List<String>? searchResults = await api.getArtistAndTracks(query);

    if (searchResults != null && searchResults.length >= 4) {
      artistName = searchResults[0];
      trackName = searchResults[1];
      artistUrl = searchResults[2];
      trackUrl = searchResults[3];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTextMode = widget.texts_or_speech == 'texts';
    final String currentLanguage = widget.languageLabel ?? '國語歌';

    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;

    return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 40),
            onPressed: () => context.pop(),
          ),
        ),
        body: SingleChildScrollView(
          //  加上 SizedBox 強迫寬度撐滿整個螢幕
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                //  因為外面撐滿了螢幕，這裡的 center 就會讓所有東西置中
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: size.height * 0.05),

                  // 以前聽過的歌
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '以前聽過的歌',
                      style: TextStyle(
                          fontSize: (screenWidth * 0.06).clamp(20.0, 40.0),
                          color: Colors.black87
                      ),
                    ),
                  ),
                  SizedBox(height: size.height * 0.1),

                  // 國語歌
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF59D), // 淺黃色
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      currentLanguage,
                      style: TextStyle(
                          fontSize: (screenWidth * 0.06).clamp(20.0, 40.0),
                          color: Colors.black87
                      ),
                    ),
                  ),

                  // 依據螢幕高度動態推開下方區域
                  SizedBox(height: size.height * 0.1),

                  // 條件渲染區塊
                  if (isTextMode)
                    _buildTextInputUI(screenWidth)
                  else
                    _buildSpeechInputUI(screenWidth),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        )
    );
  }

  // 獨立出來的文字輸入 UI
  Widget _buildTextInputUI(double screenWidth) {
    return Column(
      children: [
        SizedBox(
          //  寬度佔螢幕 80%，限制在 250~400 之間
          width: (screenWidth * 0.8).clamp(250.0, 400.0),
          child: TextField(
            controller: _textController,
            textAlign: TextAlign.center,
            cursorColor: Colors.white,
            cursorWidth: 4.0,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (String value) async {
              if (value.trim().isEmpty) {
                _showEmptyWarning();
                return;
              }
              speechText = value;
              await _setEmbedUrls(value);
              _navigateToNextPage();
            },
            decoration: InputDecoration(
              hintText: "請在此輸入歌手及歌名，例如: 葛蘭 我要你的愛",
              hintStyle: const TextStyle(color: Colors.black38, fontSize: 18),
              filled: true,
              fillColor: const Color(0xFFFDE065),
              contentPadding: const EdgeInsets.symmetric(vertical: 24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(fontSize: 28, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 32),
        // 下方提示文字
        const Text(
          "文字輸入中",
          style: TextStyle(fontSize: 24, color: Colors.black87),
        ),
      ],
    );
  }

  // 獨立出來的語音輸入 UI
  Widget _buildSpeechInputUI(double screenWidth) {
    //  根據螢幕寬度動態計算麥克風圓形的大小
    final double circleSize = (screenWidth * 0.35).clamp(120.0, 160.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: () {
            if(_isRecording) {
              setState(() => _isRecording = false);
              _voiceManager.forceEndChat();
            } else {
              _startRecordingSession();
            }
          },
          borderRadius: BorderRadius.circular(100),
          child: Container(
            width: circleSize,
            height: circleSize,
            decoration: const BoxDecoration(
              color: Color(0xFFFDE065),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isRecording ? Icons.stop : Icons.mic,
              size: circleSize * 0.5, //  Icon 大小永遠是圓形的一半
              color: _isRecording ? Colors.red : Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 32),
        // 下方提示文字
        Text(
          _isRecording ? "錄音中..." : "開始",
          style: const TextStyle(fontSize: 24, color: Colors.black87),
        ),
      ],
    );
  }
}