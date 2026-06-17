import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/services/spotify_api_services.dart';
import 'package:remini_care_ai_app/services/voice_assistant_services.dart';

import 'package:remini_care_ai_app/services/speech_services.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

class SearchByTextsOrSpeech extends StatefulWidget {
  final String? texts_or_speech;
  final String? languageLabel;
  const SearchByTextsOrSpeech({super.key, this.texts_or_speech, this.languageLabel});

  @override
  State<StatefulWidget> createState() => _SearchByTextsOrSpeechState();
}

class _SearchByTextsOrSpeechState extends State<SearchByTextsOrSpeech> {
  // 使用 Controller 來管理輸入框的文字
  final TextEditingController _textController = TextEditingController(text: '我要你的愛');
  final String spotifyClientId = ReminiCareConfig.spotifyClientId;
  final String spotifyClientSecret = ReminiCareConfig.spotifyClientSecret;
  late String? artistName;
  late String? trackName;
  late String? artistUrl;
  late String? trackUrl;
  String? languageLabel;

  final ISTTService sttService = YatingSpeechService();
  final _voiceManager = VoiceAssistantManager();
  bool _isRecording = false;
  String? speechText;
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
      _navigateToNextPage();
    };

    _voiceManager.startBackgroundWakeWordCycle();
  }

  void _startRecordingSession() {
    setState(() { _isRecording = true; });
    _voiceManager.startChatFlow(); // 啟動助理錄製
  }

  Future<void> _processMergedAudio(List<String>? paths) async {
    setState(() { _isRecording = false; });
    print("取得無損拼接回憶 WAV 檔 (共 ${paths?.length ?? 0} 段)");

    String fullTranscript = "";

    // 💡 逐段送交成大自研 ASR 解析並合併字串
    if (paths != null && paths.isNotEmpty) {
      for (String path in paths) {
        final result = await sttService.transcribe(path);
        try { File(path).deleteSync(); } catch (_) {} // 解析完順手刪除暫存

        if (result != null && result.trim().isNotEmpty) {
          fullTranscript += result; // 歌名搜尋直接緊湊拼接即可
        }
      }
    }

    if (fullTranscript.isNotEmpty) {
      speechText = fullTranscript;
      _textController.text = fullTranscript; // 同步將辨識出的歌名丟到文字框，效果很炫

      // 💡 一次性全自動解析 Spotify 網址並直接切換下一頁！長輩連動手都不用！
      _navigateToNextPage();
    } else {
      // 如果是靜音或辨識失敗，重啟背景監聽
      _voiceManager.checkCompletedCommands = false;
      _voiceManager.startBackgroundWakeWordCycle();
    }
  }

  void _navigateToNextPage() async {
    // 這裡放你的跳轉邏輯，並把輸入的文字 (value) 帶過去
    // 假設你的下一個頁面路由叫做 /search_results
    if(speechText == null) speechText = "";
    await _setEmbedUrls(speechText!);
    final queryParams = {
      'artistUrl': artistUrl,
      'trackUrl': trackUrl,
    };
    final uri = Uri(
        path: '/search_results/$artistName/$trackName/$languageLabel',
        queryParameters: queryParams
    ).toString();
    context.push(uri);
  }

  @override
  void initState() {
    super.initState();
    _initVoiceAssistant();
    languageLabel = widget.languageLabel;
  }

  @override
  void dispose() {
    _textController.dispose(); // 記得釋放資源
    _voiceManager.dispose();
    super.dispose();
  }

  Future<void> _setEmbedUrls(String query) async {
    final spotifyApiServices = SpotifyApiServices(
      spotifyClientId,
      spotifyClientSecret
    );
    final List<String>? spotifySearchResults = await spotifyApiServices.getArtistAndTracks(query) as List<String>;
    artistName = spotifySearchResults?[0];
    trackName = spotifySearchResults?[1];
    artistUrl = spotifySearchResults?[2];
    trackUrl = spotifySearchResults?[3];
  }

  @override
  Widget build(BuildContext context) {
    // 判斷當前是否為文字模式
    final bool isTextMode = widget.texts_or_speech == 'texts';
    final String currentLanguage = widget.languageLabel ?? '國語歌';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '以前聽過的歌',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              Text(
                currentLanguage,
                style: const TextStyle(fontSize: 60, color: Colors.black87),
              ),
              const SizedBox(height: 60),

              // 2. 條件渲染區塊：根據變數決定顯示文字輸入還是語音按鈕
              if (isTextMode)
                _buildTextInputUI(currentLanguage)
              else
                _buildSpeechInputUI(currentLanguage),
              SizedBox(height: 40),
              Text(_isRecording ? "手動結束錄音" : "手動開始錄音"),
              SizedBox(height: 40),
              Text(_isRecording ? "🎙️ 正在錄製故事中..." : "🤖 背景語音助理監聽中..."),
            ],
          ),
        ),
      )
    );
  }

  // 獨立出來的文字輸入 UI
  Widget _buildTextInputUI(String languageLabel) {
    return SizedBox(
      width: 220, // 限制輸入框的寬度
      child: TextField(
        controller: _textController,
        textAlign: TextAlign.center, // 讓文字置中
        cursorColor: Colors.white, // 模仿截圖中的白色游標
        cursorWidth: 3.0,
        autofocus: true, // 進來這頁自動彈出鍵盤

        // 將鍵盤右下角的按鈕設為「搜尋」樣式
        textInputAction: TextInputAction.search,

        // 當使用者按下鍵盤的搜尋/確認鍵時觸發
        onSubmitted: (String value) async {
          // 防呆機制：如果使用者沒打字就按搜尋，可以直接 return 不做任何事
          if (value.trim().isEmpty) return;
          await _setEmbedUrls(value);
          // 這裡放你的跳轉邏輯，並把輸入的文字 (value) 帶過去
          // 假設你的下一個頁面路由叫做 /search_results
          final queryParams = {
            'artistUrl': artistUrl,
            'trackUrl': trackUrl,
          };
          final uri = Uri(
            path: '/search_results/$artistName/$trackName/$languageLabel',
            queryParameters: queryParams
          ).toString();
          context.push(uri);
        },

        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.grey[300], // 淺灰背景色
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none, // 移除預設的黑框
          ),
        ),
        style: const TextStyle(fontSize: 18),
      ),
    );
  }

  // 獨立出來的語音輸入 UI
  Widget _buildSpeechInputUI(String languageLabel) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle, // 圓形背景
      ),
      child:Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              _isRecording ? Icons.stop : Icons.mic,
              size: 40,
              color: _isRecording ? Colors.red : Colors.black87,
            ),
            onPressed: () {
              // 這裡可以觸發開啟麥克風的邏輯
              if(_isRecording) {
                setState(() {
                  _isRecording = false;
                });
                _voiceManager.forceEndChat();
              }
              else {
                _startRecordingSession();
              }
            },
          ),
        ],
      )
    );
  }

}