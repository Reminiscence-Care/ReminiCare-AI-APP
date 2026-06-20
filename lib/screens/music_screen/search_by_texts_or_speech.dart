import 'dart:convert';
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

  List<Map<String, String>> top5Songs = [];

  String? languageLabel;
  final ISTTService sttService = YatingSpeechService();
  final _voiceManager = VoiceAssistantManager();

  bool _isRecording = false;
  bool _isCalibrating = true; // 環境音檢測狀態標記
  bool _isProcessing = false; // 💡 新增：正在辨識與搜尋的 Loading 狀態標記

  String? speechText;

  @override
  void initState() {
    super.initState();
    _initVoiceAssistant();
    languageLabel = widget.languageLabel;

    // 等待 2 秒鐘讓底層 VoiceManager 完成環境雜音採樣 (約需 1.6 秒)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isCalibrating = false;
        });
      }
    });
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

    // 這裡啟動後，底層就開始進行 1.6 秒的背景雜音校正
    _voiceManager.startBackgroundWakeWordCycle();
  }

  void _startRecordingSession() {
    setState(() { _isRecording = true; });
    _voiceManager.startChatFlow();
  }

  Future<void> _processMergedAudio(List<String>? paths) async {
    // 💡 錄音結束，進入處理狀態
    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });
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
      // 💡 處理失敗或無聲音，解除 Loading 狀態
      setState(() { _isProcessing = false; });
      _showEmptyWarning("請先說出想聽的歌哦！");
      _voiceManager.checkCompletedCommands = false;
      _voiceManager.startBackgroundWakeWordCycle();
    }
  }

  void _navigateToNextPage() async {
    // 💡 在準備跳轉前解除 Loading，這樣如果使用者按返回鍵回來，才不會卡在轉圈圈
    setState(() { _isProcessing = false; });

    if(top5Songs.isEmpty) {
      _showEmptyWarning("搜尋不到結果，請重新搜尋!");
      return;
    }
    final safeLang = languageLabel ?? '國語歌';
    final queryParams = {
      'languageLabel': safeLang,
      'songsData': jsonEncode(top5Songs),
    };

    final uri = Uri(
        path: '/search_results',
        queryParameters: queryParams
    ).toString();

    if (mounted) context.push(uri);
  }

  void _showEmptyWarning(String warningStr) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lightbulb_outline, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Text(
              warningStr,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFFA726), // 溫和的橘色
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
    final List<Map<String, String>>? searchResults = await api.getTop5ArtistAndTracks(query);

    if (searchResults != null && searchResults.isNotEmpty) {
      top5Songs = searchResults;
    } else {
      top5Songs = [];
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
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
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
          width: (screenWidth * 0.8).clamp(250.0, 400.0),
          child: TextField(
            controller: _textController,
            textAlign: TextAlign.center,
            cursorColor: Colors.white,
            cursorWidth: 4.0,
            autofocus: true,
            textInputAction: TextInputAction.search,
            // 💡 文字模式在處理時也禁用輸入框
            enabled: !_isProcessing,
            onSubmitted: (String value) async {
              if (value.trim().isEmpty) {
                _showEmptyWarning("請先輸入想聽的歌哦！");
                return;
              }
              // 💡 點擊鍵盤送出後，也顯示 Loading 狀態
              setState(() { _isProcessing = true; });
              speechText = value;
              await _setEmbedUrls(value);
              _navigateToNextPage();
            },
            decoration: InputDecoration(
              hintText: "請在此輸入歌手及歌名，例如: 葛蘭 我要你的愛",
              hintStyle: const TextStyle(color: Colors.black38, fontSize: 18),
              filled: true,
              fillColor: _isProcessing ? Colors.grey[300] : const Color(0xFFFDE065),
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
        Text(
          _isProcessing ? "正在搜尋歌曲..." : "文字輸入中", // 💡 文字模式 Loading 提示
          style: TextStyle(
            fontSize: 24,
            color: _isProcessing ? Colors.grey[600] : Colors.black87,
            fontWeight: _isProcessing ? FontWeight.normal : FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // 獨立出來的語音輸入 UI
  Widget _buildSpeechInputUI(double screenWidth) {
    final double circleSize = (screenWidth * 0.35).clamp(120.0, 160.0);
    // 判斷是否為「任何」不可點擊的狀態 (檢測中 or 正在搜尋處理中)
    final bool isBusy = _isCalibrating || _isProcessing;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          // 💡 檢測環境音或處理搜尋時，按鈕設為 null 使其失效，防止誤觸
          onTap: isBusy ? null : () {
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
            decoration: BoxDecoration(
              // 💡 檢測中或處理中顯示灰色，否則顯示黃色
              color: isBusy ? Colors.grey[300] : const Color(0xFFFDE065),
              shape: BoxShape.circle,
            ),
            // 💡 檢測中或處理中顯示轉圈圈，否則顯示麥克風/停止圖示
            child: isBusy
                ? Center(
              child: CircularProgressIndicator(
                color: Colors.grey[500],
                strokeWidth: 4.0,
              ),
            )
                : Icon(
              _isRecording ? Icons.stop : Icons.mic,
              size: circleSize * 0.5,
              color: _isRecording ? Colors.red : Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 32),
        // 💡 下方提示文字：根據狀態顯示不同文案
        Text(
          _isCalibrating
              ? "正在檢測環境音..."
              : _isProcessing
              ? "正在辨識並搜尋歌曲..." // 💡 新增的處理中提示
              : (_isRecording ? "錄音中..." : "開始"),
          style: TextStyle(
            fontSize: 24,
            color: isBusy ? Colors.grey[600] : Colors.black87,
            fontWeight: isBusy ? FontWeight.normal : FontWeight.bold,
          ),
        ),
      ],
    );
  }
}