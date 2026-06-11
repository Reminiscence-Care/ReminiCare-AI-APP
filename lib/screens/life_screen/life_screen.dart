import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart';

// 引入您的純 Dart 服務層
import 'package:remini_care_ai_app/services/reminicare_ai_services.dart';

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
  // 實例化純 Dart AI 客戶端服務
  final NvidiaLlmService _llmService = NvidiaLlmService();
  final SiliconFlowImageService _imageService = SiliconFlowImageService();
  final NckuTtsService _ttsService = NckuTtsService();

  // 狀態變數與播放器
  String _aiGeneratedText = "";
  String _selectedLanguage = "台語";
  ChatStatus _chatStatus = ChatStatus.prepare;

  bool _isLoading = true;
  bool _isExtractingKeywords = false;

  int _recordSeconds = 0;
  Timer? _recordTimer;

  final int _maxKeywordLength = 5;
  List<String> _originalKeywords = [];
  List<String> _newKeywords = [];

  // 保留對話紀錄以維持上下文
  final List<Map<String, String>> _chatHistory = [];
  String _currentImageUrl = "";

  final AudioPlayer _audioPlayer = AudioPlayer();

  // 語音助手變數
  final SpeechToText _speechToText = SpeechToText();
  bool _isSpeechInitialized = false;
  bool _isListening = false;
  String _lastWords = ""; // 記錄長輩即時說話內容

  @override
  void initState() {
    super.initState();
    // 💡 啟動時先動態讀取本地/SharedPreferences 金鑰，讀完才叫 LLM 出題
    _initializeConfigurationAndLoad();
  }

  /// 💡 初始化金鑰並獲取初始問題
  Future<void> _initializeConfigurationAndLoad() async {
    await ReminiCareConfig.loadConfig(); // 載入 SharedPreferences 優先的金鑰
    _fetchInitialQuestion();
    _initSpeechToText(); // 初始化語音助手
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
      _recordSeconds = 0;
      _currentImageUrl = "";
      _originalKeywords.clear();
      _newKeywords.clear();
      _chatHistory.clear();
      _aiGeneratedText = "";
      _isLoading = true;
      _stopTimer();
    });
    _fetchInitialQuestion();
    _startVoiceAssistant();
  }

  @override
  void dispose() {
    _stopTimer();
    _audioPlayer.dispose();
    _speechToText.stop();
    super.dispose();
  }

  // ==========================================
  // 🎙️ 語音助手與熱詞監聽邏輯 (免動手控制)
  // ==========================================

  /// 初始化語音助手
  Future<void> _initSpeechToText() async {
    try {
      bool available = await _speechToText.initialize(
        onStatus: (status) {
          debugPrint("[語音助手狀態] $status");
          if (status == 'notListening' && _isListening) {
            _restartListening();
          }
        },
        onError: (errorNotification) {
          debugPrint("[語音助手錯誤] $errorNotification");
          if (_isListening) {
            _restartListening();
          }
        },
      );
      if (available) {
        setState(() {
          _isSpeechInitialized = true;
        });
        _startVoiceAssistant();
      }
    } catch (e) {
      debugPrint("語音助手初始化失敗: $e");
    }
  }

  /// 啟動監聽
  void _startVoiceAssistant() async {
    if (!_isSpeechInitialized) return;
    setState(() {
      _isListening = true;
      _lastWords = "";
    });

    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
        });
        _handleVoiceCommands(_lastWords);
      },
      localeId: 'zh_TW',
      cancelOnError: false,
      partialResults: true,
      listenMode: ListenMode.dictation,
    );
  }

  /// 自動重啟監聽
  void _restartListening() {
    if (!_isListening) return;
    _speechToText.stop().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _startVoiceAssistant();
      });
    });
  }

  /// 語音指令核心分流器
  void _handleVoiceCommands(String words) {
    final String cleanWords = words.replaceAll(" ", "");
    debugPrint("[語音助手監聽中] -> $cleanWords");

    if (_chatStatus == ChatStatus.prepare ||
        _chatStatus == ChatStatus.dislikePrepare ||
        _chatStatus == ChatStatus.likePrepare) {
      if (cleanWords.contains("開始錄音") || cleanWords.contains("開始聊天")) {
        _speechToText.stop();
        _voiceTriggerStartChat();
      }
    }

    else if (_chatStatus == ChatStatus.chatting ||
        _chatStatus == ChatStatus.dislikeChatting ||
        _chatStatus == ChatStatus.likeChatting) {
      if (cleanWords.contains("結束錄音") || cleanWords.contains("結束聊天")) {
        _speechToText.stop();

        String cleanConversationText = words
            .replaceAll("結束錄音", "")
            .replaceAll("結束聊天", "")
            .trim();

        _voiceTriggerEndChat(cleanConversationText);
      }
    }

    else if (_chatStatus == ChatStatus.completed ||
        _chatStatus == ChatStatus.dislikeCompleted ||
        _chatStatus == ChatStatus.likeCompleted) {
      if (cleanWords.contains("重新錄音") || cleanWords.contains("重新聊天")) {
        _speechToText.stop();
        _voiceTriggerRestartChat();
      }
    }
  }

  // ==========================================
  // 🚀 語音指令觸發之頁面控制器
  // ==========================================

  void _voiceTriggerStartChat() {
    setState(() {
      _chatStatus = _chatStatus == ChatStatus.dislikePrepare
          ? ChatStatus.dislikeChatting
          : _chatStatus == ChatStatus.likePrepare
          ? ChatStatus.likeChatting
          : ChatStatus.chatting;
      _recordSeconds = 0;
      _startTimer();
    });
    _startVoiceAssistant();
  }

  void _voiceTriggerEndChat(String conversationText) {
    _stopTimer();
    setState(() {
      _chatStatus = _chatStatus == ChatStatus.dislikeChatting
          ? ChatStatus.dislikeCompleted
          : _chatStatus == ChatStatus.likeChatting
          ? ChatStatus.likeCompleted
          : ChatStatus.completed;
    });
    _processAudioAndChat(manualText: conversationText);
    _startVoiceAssistant();
  }

  void _voiceTriggerRestartChat() {
    setState(() {
      _recordSeconds = 0;
      _chatStatus = _chatStatus == ChatStatus.dislikeCompleted
          ? ChatStatus.dislikeChatting
          : _chatStatus == ChatStatus.likeCompleted
          ? ChatStatus.likeChatting
          : ChatStatus.chatting;
      _startTimer();
    });
    _startVoiceAssistant();
  }

  // ==========================================
  // 🚀 純 Dart 業務呼叫邏輯 (UI 部分)
  // ==========================================

  Future<void> _playVoice(String text, String language) async {
    if (text.isEmpty) return;
    try {
      if (kIsWeb) return;
      final Uint8List? audioBytes = await _ttsService.generateSpeech(text, language);
      if (audioBytes != null) {
        await _audioPlayer.play(BytesSource(audioBytes));
      }
    } catch (e) {
      debugPrint("[播放錯誤]: $e");
    }
  }

  void _playCurrentContextVoice(String lang) {
    setState(() => _selectedLanguage = lang);
    String textToPlay = _aiGeneratedText;

    if (_chatStatus == ChatStatus.evaluation || _chatStatus == ChatStatus.dislikeEvaluation) {
      textToPlay = "這張圖符合您的回憶嗎？";
    } else if (_chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeChatting || _chatStatus == ChatStatus.dislikeCompleted) {
      textToPlay = "哪裡不對？";
    } else if (_chatStatus == ChatStatus.likePrepare || _chatStatus == ChatStatus.likeChatting || _chatStatus == ChatStatus.likeCompleted) {
      textToPlay = "這張圖片讓您想到什麼？";
    }

    _playVoice(textToPlay, lang);
  }

  Future<void> _fetchInitialQuestion() async {
    setState(() { _isLoading = true; });
    try {
      final String question = await _llmService.generateInitialQuestion();
      setState(() {
        _aiGeneratedText = question;
      });
    } catch (e) {
      debugPrint("初始問題獲取失敗: $e");
      setState(() {
        _aiGeneratedText = "哈囉！小時候家裡最常吃什麼呢？";
      });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _processAudioAndChat({String? manualText}) async {
    setState(() { _isExtractingKeywords = true; });
    String userMessage = "";

    try {
      if (manualText != null && manualText.isNotEmpty) {
        userMessage = manualText;
        debugPrint("[語音助手即時文本] 解析成功: $userMessage");
      } else {
        if (_chatStatus == ChatStatus.completed) {
          userMessage = "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";
        } else if (_chatStatus == ChatStatus.dislikeCompleted) {
          userMessage = "這張不像啦，桌上只有一鍋蕃薯粥配醃蘿蔔而已。";
        } else {
          userMessage = "兄弟姊妹都會去山上摸魚。";
        }
      }

      final String reply = await _llmService.generateChatReply(userMessage, _chatHistory);
      final List<String> extracted = await _llmService.extractKeywords(userMessage);

      setState(() {
        _aiGeneratedText = reply;
        if (_chatStatus == ChatStatus.completed || _chatStatus == ChatStatus.keywords) {
          _originalKeywords = extracted;
        } else {
          _newKeywords = extracted;
        }
      });

      _chatHistory.add({"role": "user", "content": userMessage});
      _chatHistory.add({"role": "assistant", "content": reply});

    } catch (e) {
      debugPrint("陪伴與萃取流發生錯誤: $e");
      setState(() {
        _aiGeneratedText = "拍謝，我剛才恍神沒聽清楚，可以再說一次嗎？";
      });
    } finally {
      setState(() { _isExtractingKeywords = false; });
    }
  }

  Future<void> _triggerImageGeneration() async {
    setState(() { _chatStatus = ChatStatus.generating; });
    try {
      String prompt = _originalKeywords.join("、");
      if (prompt.isEmpty) prompt = "懷舊場景";

      final String? imageUrl = await _imageService.generateNostalgicImage(
        scene: "在傳統灶腳烹飪, 包含關鍵元素: $prompt",
        era: "1980s",
        location: "Taiwan",
      );

      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.evaluation;
        });
      } else {
        throw Exception("生圖出錯");
      }
    } catch (e) {
      debugPrint("生圖流程出錯: $e");
      setState(() { _chatStatus = ChatStatus.keywords; });
    }
  }

  Future<void> _triggerModifiedImageGeneration() async {
    setState(() { _chatStatus = ChatStatus.dislikeGenerating; });
    try {
      String combinedPrompt = _newKeywords.join("、");
      if (combinedPrompt.isEmpty) combinedPrompt = "修改後的食物與場景";

      final String? imageUrl = await _imageService.editImage(
        imagePath: _currentImageUrl,
        editInstruction: "將桌上的食物與細節修改或新增為: $combinedPrompt",
      );

      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.dislikeEvaluation;
        });
      } else {
        throw Exception("改圖出錯");
      }
    } catch (e) {
      debugPrint("改圖流程出錯: $e");
      setState(() { _chatStatus = ChatStatus.dislikeKeywords; });
    }
  }

  Future<void> _triggerLikeExtendedImageGeneration() async {
    setState(() { _chatStatus = ChatStatus.likeGenerating; });
    try {
      String combinedPrompt = [..._originalKeywords, ..._newKeywords].join("、");

      final String? imageUrl = await _imageService.generateNostalgicImage(
        scene: "一個溫馨的台灣家庭回憶場景, 包含關鍵元素: $combinedPrompt",
        era: "1980s",
        location: "Taiwan",
      );

      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.evaluation;
        });
      } else {
        throw Exception("延伸話題生圖出錯");
      }
    } catch (e) {
      debugPrint("延伸生圖流程出錯: $e");
      setState(() { _chatStatus = ChatStatus.likeKeywords; });
    }
  }

  // ==========================================
  // ⚙️ 互動式自訂設定視窗 (完美修復：支援眼睛點擊查看與隱蔽)
  // ==========================================
  void _showSettingsDialog() {
    final nvidiaController = TextEditingController(text: ReminiCareConfig.nvidiaApiKey);
    final groqController = TextEditingController(text: ReminiCareConfig.groqApiKey);
    final siliconFlowController = TextEditingController(text: ReminiCareConfig.siliconFlowApiKey);
    final ttsTokenController = TextEditingController(text: ReminiCareConfig.nckuTtsToken);

    // 💡 定義四個文字框對應的 obscureText 隱私開關狀態，預設皆為遮罩(true)
    bool obscureNvidia = true;
    bool obscureGroq = true;
    bool obscureSilicon = true;
    bool obscureTts = true;

    showDialog(
      context: context,
      barrierDismissible: false, // 必須手動點按鈕關閉
      builder: (BuildContext context) {
        // 💡 關鍵：使用 StatefulBuilder 來讓 Dialog 的 setStateDialog 觸發局部更新，解決 Dialog 無法重繪的問題
        return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: const [
                    Icon(Icons.settings, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Text("ReminiCare AI 金鑰配置", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "金鑰儲存於您手機的本機安全資料庫中，您的機密不會外洩。設定完成後立即套用生效！",
                          style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        // 💡 傳入 obscure 狀態，並在 onPressed 閉包中翻轉 boolean 值
                        _buildSettingsField(
                            "NVIDIA API KEY",
                            nvidiaController,
                            "nvapi-...",
                            obscureNvidia,
                                () {
                              setStateDialog(() {
                                obscureNvidia = !obscureNvidia;
                              });
                            }
                        ),
                        _buildSettingsField(
                            "GROQ API KEY (STT)",
                            groqController,
                            "gsk_...",
                            obscureGroq,
                                () {
                              setStateDialog(() {
                                obscureGroq = !obscureGroq;
                              });
                            }
                        ),
                        _buildSettingsField(
                            "SILICONFLOW KEY",
                            siliconFlowController,
                            "sk-...",
                            obscureSilicon,
                                () {
                              setStateDialog(() {
                                obscureSilicon = !obscureSilicon;
                              });
                            }
                        ),
                        _buildSettingsField(
                            "NCKU TTS TOKEN",
                            ttsTokenController,
                            "Token...",
                            obscureTts,
                                () {
                              setStateDialog(() {
                                obscureTts = !obscureTts;
                              });
                            }
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("取消", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      // 1. 永久保存到本地 SQLite / SharedPreferences
                      await ReminiCareConfig.saveConfig(
                        nvidia: nvidiaController.text,
                        groq: groqController.text,
                        siliconFlow: siliconFlowController.text,
                        ttsToken: ttsTokenController.text,
                      );

                      if (context.mounted) {
                        Navigator.of(context).pop();

                        // 2. 貼心提示使用者金鑰已更新
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("🎉 金鑰更新成功！系統已立即載入新金鑰運作。"),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );

                        // 3. 即時重新觸發取得問題，驗證新 Key
                        _fetchInitialQuestion();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("儲存並套用", style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  /// 💡 自定義設定框組件：支持動態控制密碼顯隱
  Widget _buildSettingsField(
      String label,
      TextEditingController controller,
      String hint,
      bool obscureText,
      VoidCallback onToggleVisibility,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        obscureText: obscureText, // 💡 使用動態傳入的布林值
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: IconButton(
            // 💡 依據 obscureText 的值動態更新眼睛圖示（開眼與閉眼）
            icon: Icon(
              obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
            ),
            onPressed: onToggleVisibility, // 💡 觸發外界狀態更新
          ),
        ),
      ),
    );
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
        // 💡 頂部 AppBar 右側新增一個齒輪按鈕，方便隨時打開金鑰設定頁面
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black87),
            onPressed: _showSettingsDialog,
            tooltip: "設定 API 金鑰",
          ),
          const SizedBox(width: 8),
        ],
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
                              onLanguageSelected: _playCurrentContextVoice,
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

                          _buildVoiceAssistantIndicator(),

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

  /// 語音助手提示條
  Widget _buildVoiceAssistantIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _isListening ? Colors.green[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _isListening ? Colors.green[200]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isListening ? Icons.mic : Icons.mic_off,
              color: _isListening ? Colors.green[700] : Colors.grey[600],
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              _isListening
                  ? (_chatStatus == ChatStatus.chatting || _chatStatus == ChatStatus.dislikeChatting || _chatStatus == ChatStatus.likeChatting
                  ? "說「結束錄音」可自動分析回憶"
                  : "聽候指令中：說「開始錄音」或「重新錄音」")
                  : "語音助理未啟動",
              style: TextStyle(
                fontSize: 12,
                color: _isListening ? Colors.green[800] : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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
          onStartChat: _voiceTriggerStartChat,
        );
      case ChatStatus.chatting:
        return ListeningView(
          recordSeconds: _recordSeconds,
          onEndRecording: () async {
            _speechToText.stop();
            _voiceTriggerEndChat(_lastWords);
          },
        );
      case ChatStatus.completed:
        return CompletedView(
          onRestartChat: _voiceTriggerRestartChat,
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
          },
          onDislike: () {
            setState(() { _chatStatus = ChatStatus.dislikePrepare; });
          },
        );
      case ChatStatus.dislikePrepare:
        return DislikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: _voiceTriggerStartChat,
        );
      case ChatStatus.dislikeChatting:
        return DislikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: () async {
            _speechToText.stop();
            _voiceTriggerEndChat(_lastWords);
          },
        );
      case ChatStatus.dislikeCompleted:
        return CompletedView(
          onRestartChat: _voiceTriggerRestartChat,
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
          },
          onFinished: _resetAllStates,
        );
      case ChatStatus.likePrepare:
        return LikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: _voiceTriggerStartChat,
        );
      case ChatStatus.likeChatting:
        return LikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: () async {
            _speechToText.stop();
            _voiceTriggerEndChat(_lastWords);
          },
        );
      case ChatStatus.likeCompleted:
        return CompletedView(
          onRestartChat: _voiceTriggerRestartChat,
          onEndChat: () { setState(() { _chatStatus = ChatStatus.likeKeywords; }); },
        );
      case ChatStatus.likeKeywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerLikeExtendedImageGeneration);
      case ChatStatus.likeGenerating:
        return const GeneratingView();
    }
  }
}