import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';

// 匯入您自定義的子組件
import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/keywords_view.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';

enum ChatStatus {
  prepare, chatting, completed, keywords, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeCompleted, dislikeKeywords, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeCompleted, likeKeywords, likeGenerating,
}

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  // ==========================================
  // 🔗 API 伺服器設定
  // ==========================================
  final String apiBaseUrl = "http://127.0.0.1:8000/api";

  // ==========================================
  // 狀態變數與語音播放器
  // ==========================================
  String _aiGeneratedText = "";
  String _selectedLanguage = "台語";
  ChatStatus _chatStatus = ChatStatus.prepare;

  bool _isLoading = true;
  bool _isExtractingKeywords = false;

  int _recordSeconds = 205;
  Timer? _recordTimer;

  final int _maxKeywordLength = 5;
  List<String> _originalKeywords = [];
  List<String> _newKeywords = [];
  List<Map<String, String>> _chatHistory = [];
  String _currentImageUrl = "";

  // 實例化音訊播放器
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _fetchInitialQuestion();
  }

  // ==========================================
  // 計時器管理與狀態重置
  // ==========================================
  void _startTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() { _recordSeconds++; });
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void _resetAllStates() {
    setState(() {
      _chatStatus = ChatStatus.prepare;
      _recordSeconds = 205;
      _currentImageUrl = "";
      _originalKeywords.clear();
      _newKeywords.clear();
      _chatHistory.clear();
      _aiGeneratedText = "";
      _isLoading = true;
      _stopTimer();
    });
    _fetchInitialQuestion();
  }

  @override
  void dispose() {
    _stopTimer();
    _audioPlayer.dispose(); // 釋放播放器資源
    super.dispose();
  }

  // ==========================================
  // 🚀 核心 API 串接邏輯
  // ==========================================

  /// 播放語音 API 串接 (手動觸發)
  Future<void> _playVoice(String text, String language) async {
    if (text.isEmpty) return;
    try {
      // 編碼防止中文或符號造成網址錯誤
      String encodedText = Uri.encodeComponent(text);
      String encodedLang = Uri.encodeComponent(language);
      String url = '$apiBaseUrl/tts?text=$encodedText&language=$encodedLang';

      // 直接播放串流，無需下載檔案
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint("播放語音發生錯誤: $e");
    }
  }

  /// 當按下中文/台語播放按鈕時，手動播放當下文字的語音
  void _playCurrentContextVoice(String lang) {
    setState(() => _selectedLanguage = lang);
    String textToPlay = _aiGeneratedText;

    // 依據目前狀態判斷要唸什麼句子
    if (_chatStatus == ChatStatus.evaluation || _chatStatus == ChatStatus.dislikeEvaluation) {
      textToPlay = "這張圖符合您的回憶嗎？";
    } else if (_chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeChatting || _chatStatus == ChatStatus.dislikeCompleted) {
      textToPlay = "哪裡不對？";
    } else if (_chatStatus == ChatStatus.likePrepare || _chatStatus == ChatStatus.likeChatting || _chatStatus == ChatStatus.likeCompleted) {
      textToPlay = "這張圖片讓您想到什麼？";
    }

    _playVoice(textToPlay, lang);
  }

  /// 0. 獲取初始隨機問題
  Future<void> _fetchInitialQuestion() async {
    setState(() { _isLoading = true; });
    try {
      var response = await http.get(Uri.parse('$apiBaseUrl/generate_initial_question'));
      if (response.statusCode == 200) {
        var data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _aiGeneratedText = data['question'];
        });
        // 💡 移除自動播放語音：現在不主動調用 _playVoice()
      } else {
        throw Exception("獲取初始問題失敗");
      }
    } catch (e) {
      debugPrint("API 錯誤: $e");
      setState(() {
        _aiGeneratedText = "哈囉！小時候家裡最常吃什麼呢？";
      });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  /// 1. 語音轉文字 (STT) + 聊天與擷取關鍵字
  Future<void> _processAudioAndChat({String? audioPath}) async {
    setState(() { _isExtractingKeywords = true; });
    String userMessage = "";

    try {
      if (audioPath != null && !kIsWeb && File(audioPath).existsSync()) {
        var request = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/transcribe'));
        request.files.add(await http.MultipartFile.fromPath('audio_file', audioPath));
        var response = await request.send();
        var resData = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          userMessage = jsonDecode(resData)['transcript'];
        } else {
          throw Exception("語音辨識失敗");
        }
      } else {
        // [測試用假資料]
        if (_chatStatus == ChatStatus.completed) {
          userMessage = "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";
        } else if (_chatStatus == ChatStatus.dislikeCompleted) {
          userMessage = "這張不像啦，桌上只有一鍋蕃薯粥配醃蘿蔔而已。";
        } else {
          userMessage = "兄弟姊妹都會去山上摸魚。";
        }
      }

      var chatRes = await http.post(
          Uri.parse('$apiBaseUrl/chat_and_extract'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_message": userMessage,
            "chat_history": _chatHistory
          })
      );

      if (chatRes.statusCode == 200) {
        var data = jsonDecode(utf8.decode(chatRes.bodyBytes));

        setState(() {
          _aiGeneratedText = data['reply'];

          List<String> extracted = List<String>.from(data['keywords'] ?? []);
          if (_chatStatus == ChatStatus.completed) {
            _originalKeywords = extracted;
          } else {
            _newKeywords = extracted;
          }
        });

        _chatHistory.add({"role": "user", "content": userMessage});
        _chatHistory.add({"role": "assistant", "content": data['reply']});

        // 💡 移除自動播放語音：回覆時不再自動呼叫 _playVoice()
      } else {
        throw Exception("聊天與擷取 API 錯誤");
      }

    } catch (e) {
      debugPrint("API 錯誤: $e");
      setState(() {
        _aiGeneratedText = "拍謝，我剛才恍神沒聽清楚，可以再說一次嗎？";
      });
    } finally {
      setState(() { _isExtractingKeywords = false; });
    }
  }

  /// 2. 第一次確認生圖流程
  Future<void> _triggerImageGeneration() async {
    setState(() { _chatStatus = ChatStatus.generating; });
    try {
      String prompt = _originalKeywords.join("、");
      if (prompt.isEmpty) prompt = "懷舊場景";

      var response = await http.post(
          Uri.parse('$apiBaseUrl/generate_image'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"prompt_content": prompt})
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          _currentImageUrl = data['image_url'];
          _chatStatus = ChatStatus.evaluation;
        });
        // 💡 移除自動播放語音：進入評價畫面時不再主動發出聲音
      } else {
        throw Exception("生圖失敗");
      }
    } catch (e) {
      setState(() { _chatStatus = ChatStatus.keywords; });
    }
  }

  /// 3. 第二次確認生圖流程 (改圖)
  Future<void> _triggerModifiedImageGeneration() async {
    setState(() { _chatStatus = ChatStatus.dislikeGenerating; });
    try {
      String combinedPrompt = [..._originalKeywords, ..._newKeywords].join("、");
      var response = await http.post(
          Uri.parse('$apiBaseUrl/generate_image'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"prompt_content": combinedPrompt})
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          _currentImageUrl = data['image_url'];
          _chatStatus = ChatStatus.dislikeEvaluation;
        });
        // 💡 移除自動播放語音
      } else {
        throw Exception("修改生圖失敗");
      }
    } catch (e) {
      setState(() { _chatStatus = ChatStatus.dislikeKeywords; });
    }
  }

  /// 4. 「像」延伸話題確認生圖流程 (新生圖)
  Future<void> _triggerLikeExtendedImageGeneration() async {
    setState(() { _chatStatus = ChatStatus.likeGenerating; });
    try {
      String combinedPrompt = [..._originalKeywords, ..._newKeywords].join("、");
      var response = await http.post(
          Uri.parse('$apiBaseUrl/generate_image'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"prompt_content": combinedPrompt})
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          _currentImageUrl = data['image_url'];
          _chatStatus = ChatStatus.evaluation;
        });
        // 💡 移除自動播放語音
      } else {
        throw Exception("延伸話題生圖失敗");
      }
    } catch (e) {
      setState(() { _chatStatus = ChatStatus.likeKeywords; });
    }
  }

  // ==========================================
  // 主畫面排版
  // ==========================================
  @override
  Widget build(BuildContext context) {
    String appBarTitle = "";
    switch (_chatStatus) {
      case ChatStatus.prepare: appBarTitle = "準備聊天"; break;
      case ChatStatus.chatting:
      case ChatStatus.completed: appBarTitle = "點開始聊"; break;
      case ChatStatus.keywords: appBarTitle = "抓取關鍵詞"; break;
      case ChatStatus.generating:
      case ChatStatus.dislikeGenerating:
      case ChatStatus.likeGenerating: appBarTitle = "Ai 生圖中"; break;
      case ChatStatus.evaluation:
      case ChatStatus.dislikeEvaluation: appBarTitle = "問像不像"; break;
      case ChatStatus.dislikePrepare:
      case ChatStatus.dislikeChatting:
      case ChatStatus.dislikeCompleted:
      case ChatStatus.dislikeKeywords: appBarTitle = "不像，繼續聊天"; break;
      case ChatStatus.likePrepare:
      case ChatStatus.likeChatting:
      case ChatStatus.likeCompleted:
      case ChatStatus.likeKeywords: appBarTitle = "如果像，就 AI延伸話題"; break;
    }

    final bool showImageOnTop = _chatStatus == ChatStatus.evaluation ||
        _chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeChatting ||
        _chatStatus == ChatStatus.dislikeCompleted || _chatStatus == ChatStatus.dislikeKeywords ||
        _chatStatus == ChatStatus.dislikeEvaluation || _chatStatus == ChatStatus.likePrepare ||
        _chatStatus == ChatStatus.likeChatting || _chatStatus == ChatStatus.likeCompleted ||
        _chatStatus == ChatStatus.likeKeywords;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          appBarTitle,
          style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Spacer(flex: 1),

                          if (showImageOnTop) ...[
                            _buildEvaluationImage(),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus != ChatStatus.evaluation && _chatStatus != ChatStatus.dislikePrepare &&
                              _chatStatus != ChatStatus.dislikeChatting && _chatStatus != ChatStatus.likePrepare &&
                              _chatStatus != ChatStatus.likeChatting && _chatStatus != ChatStatus.dislikeEvaluation) ...[
                            LanguageSelector(
                              selectedLanguage: _selectedLanguage,
                              onLanguageSelected: _playCurrentContextVoice, // 使用合併播放的方法
                            ),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus != ChatStatus.evaluation && _chatStatus != ChatStatus.dislikeEvaluation &&
                              _chatStatus != ChatStatus.dislikePrepare && _chatStatus != ChatStatus.dislikeChatting &&
                              _chatStatus != ChatStatus.likePrepare && _chatStatus != ChatStatus.likeChatting) ...[
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isLoading
                                  ? const QuestionLoadingIndicator()
                                  : QuestionArea(questionText: _aiGeneratedText),
                            ),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus == ChatStatus.keywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: const [],
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ] else if (_chatStatus == ChatStatus.dislikeKeywords || _chatStatus == ChatStatus.likeKeywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: _newKeywords,
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ],

                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _buildControlSection(),
                          ),

                          const Spacer(flex: 2),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
        ),
      ),
    );
  }

  Widget _buildEvaluationImage() {
    return Container(
      width: 320,
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
      ),
      clipBehavior: Clip.antiAlias,
      child: _currentImageUrl.isNotEmpty
          ? (_currentImageUrl.startsWith('http') || _currentImageUrl.startsWith('https')
          ? Image.network(
        _currentImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.grey)));
        },
      )
          : (kIsWeb
          ? const Center(
        child: Text(
          'Web 瀏覽器無法讀取電腦硬碟檔案\n\n請改用 Windows 桌面版執行\n(或更新後端提供靜態網址)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      )
          : Image.file(
        File(_currentImageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
      )))
          : const Center(child: Icon(Icons.image, size: 64, color: Colors.grey)),
    );
  }

  Widget _buildControlSection() {
    switch (_chatStatus) {
      case ChatStatus.prepare:
        return PrepareView(
          onStartChat: () {
            setState(() { _chatStatus = ChatStatus.chatting; _recordSeconds = 205; _startTimer(); });
          },
        );
      case ChatStatus.chatting:
        return ListeningView(
          recordSeconds: _recordSeconds,
          onEndRecording: () {
            setState(() { _chatStatus = ChatStatus.completed; _stopTimer(); });
            _processAudioAndChat();
          },
        );
      case ChatStatus.completed:
        return CompletedView(
          onRestartChat: () {
            setState(() { _chatStatus = ChatStatus.chatting; _recordSeconds = 205; _startTimer(); });
          },
          onEndChat: () {
            setState(() { _chatStatus = ChatStatus.keywords; });
          },
        );
      case ChatStatus.keywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerImageGeneration);
      case ChatStatus.generating:
        return const GeneratingView();
      case ChatStatus.evaluation:
        return EvaluationView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onLike: () {
            setState(() { _chatStatus = ChatStatus.likePrepare; });
            // 💡 移除自動播放語音："這張圖片讓您想到什麼？"
          },
          onDislike: () {
            setState(() { _chatStatus = ChatStatus.dislikePrepare; });
            // 💡 移除自動播放語音："哪裡不對？"
          },
        );
      case ChatStatus.dislikePrepare:
        return DislikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: () { setState(() { _chatStatus = ChatStatus.dislikeChatting; _recordSeconds = 205; _startTimer(); }); },
        );
      case ChatStatus.dislikeChatting:
        return DislikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: () {
            setState(() { _chatStatus = ChatStatus.dislikeCompleted; _stopTimer(); });
            _processAudioAndChat();
          },
        );
      case ChatStatus.dislikeCompleted:
        return CompletedView(
          onRestartChat: () { setState(() { _chatStatus = ChatStatus.dislikeChatting; _recordSeconds = 205; _startTimer(); }); },
          onEndChat: () { setState(() { _chatStatus = ChatStatus.dislikeKeywords; }); },
        );
      case ChatStatus.dislikeKeywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerModifiedImageGeneration);
      case ChatStatus.dislikeGenerating:
        return const GeneratingView();
      case ChatStatus.dislikeEvaluation:
        return DislikeEvaluationView(
          onContinueModify: () {
            setState(() { _chatStatus = ChatStatus.dislikePrepare; });
            // 💡 移除自動播放語音
          },
          onFinished: _resetAllStates,
        );
      case ChatStatus.likePrepare:
        return LikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: () { setState(() { _chatStatus = ChatStatus.likeChatting; _recordSeconds = 205; _startTimer(); }); },
        );
      case ChatStatus.likeChatting:
        return LikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: () {
            setState(() { _chatStatus = ChatStatus.likeCompleted; _stopTimer(); });
            _processAudioAndChat();
          },
        );
      case ChatStatus.likeCompleted:
        return CompletedView(
          onRestartChat: () { setState(() { _chatStatus = ChatStatus.likeChatting; _recordSeconds = 205; _startTimer(); }); },
          onEndChat: () { setState(() { _chatStatus = ChatStatus.likeKeywords; }); },
        );
      case ChatStatus.likeKeywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerLikeExtendedImageGeneration);
      case ChatStatus.likeGenerating:
        return const GeneratingView();
    }
  }
}