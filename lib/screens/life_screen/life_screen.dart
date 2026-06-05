import 'dart:async';
import 'package:flutter/material.dart';

// 匯入你拆分到 widgets 資料夾底下的自定義組件
import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/keywords_view.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';

/// 聊天流程的六個完整狀態：準備中、進行/聆聽中、完成、關鍵詞擷取、AI生圖中、照片評估
enum ChatStatus {
  prepare,
  chatting,
  completed,
  keywords,
  generating, // 對應 image_8be6e2.png
  evaluation, // 對應 image_8be021.png
}

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  // ==========================================
  // 狀態變數 (State Variables)
  // ==========================================
  String _aiGeneratedText = "小時候家裡最常吃什麼呢？";
  String _selectedLanguage = "台語";
  ChatStatus _chatStatus = ChatStatus.prepare;

  bool _isLoading = false;
  bool _isExtractingKeywords = false;

  int _recordSeconds = 205; // 預設錄音起始值 03:25
  Timer? _recordTimer;

  final int _maxKeywordLength = 5;
  List<String> _extractedKeywords = ["蕃薯飯", "炒青菜", "包子", "豆乾", "醃蘿蔔"];

  // ==========================================
  // 生命週期與計時器管理 (Timer Management)
  // ==========================================
  void _startTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordSeconds++;
      });
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
      _stopTimer();
    });
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  // ==========================================
  // 模擬異步 LLM / Stable Diffusion API 呼叫
  // ==========================================
  Future<void> _fetchQuestionFromLLM() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // TODO: 串接您的真實 LLM 問題生成 API
      await Future.delayed(const Duration(milliseconds: 1200));
      setState(() {
        _aiGeneratedText = "您覺得人生中最難忘的一餐是什麼？";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchKeywordsFromLLM() async {
    setState(() {
      _isExtractingKeywords = true;
    });
    try {
      // TODO: 串接您的真實 LLM 錄音擷取關鍵字 API
      await Future.delayed(const Duration(milliseconds: 1500));
      setState(() {
        _extractedKeywords = ["蕃薯飯", "炒青菜", "包子", "豆乾", "排骨酥"];
        _isExtractingKeywords = false;
      });
    } catch (e) {
      setState(() {
        _isExtractingKeywords = false;
      });
    }
  }

  /// 點擊確認生圖後的流程：生圖中 -> 照片評估
  Future<void> _triggerImageGeneration() async {
    setState(() {
      _chatStatus = ChatStatus.generating; // 先切換至：AI生圖中 (image_8be6e2)
    });

    // TODO: 串接您的影像生成 API (e.g., Midjourney, DALL-E, Stable Diffusion)
    // 這裡模擬 3 秒鐘的生圖加載時間
    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _chatStatus = ChatStatus.evaluation; // 生圖完畢，切換至：照片評估 (image_8be021)
    });
  }

  // ==========================================
  // 主畫面排版 (Main Build Method)
  // ==========================================
  @override
  Widget build(BuildContext context) {
    // 根據目前的狀態，動態改變頂部的 AppBar 標題 (比照圖片頂部標籤)
    String appBarTitle = "";
    switch (_chatStatus) {
      case ChatStatus.prepare:
        appBarTitle = "準備聊天";
        break;
      case ChatStatus.chatting:
      case ChatStatus.completed:
        appBarTitle = "點開始聊";
        break;
      case ChatStatus.keywords:
        appBarTitle = "抓取關鍵詞";
        break;
      case ChatStatus.generating:
        appBarTitle = "Ai 生圖中";
        break;
      case ChatStatus.evaluation:
        appBarTitle = "問像不像";
        break;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          appBarTitle,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // 只有在準備階段，右上角才顯示重新產生 AI 問題的 refresh 按鈕
          if (_chatStatus == ChatStatus.prepare)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.grey),
              tooltip: '重新生成問題',
              onPressed: _isLoading ? null : _fetchQuestionFromLLM,
            ),
        ],
      ),
      body: SafeArea(
        // 使用 LayoutBuilder 與 ConstrainedBox，能自動適應手機螢幕大小，防止鍵盤彈出或版面擠壓造成 Overflow
        child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Spacer(flex: 1),

                          // 1. 頂部語言選擇器 (水平排列)
                          // 注意：當進入 "evaluation" 評價照片畫面時，要隱藏這個，因為評價畫面已經整合了「垂直排列」的語言選擇器
                          if (_chatStatus != ChatStatus.evaluation)
                            LanguageSelector(
                              selectedLanguage: _selectedLanguage,
                              onLanguageSelected: (lang) {
                                setState(() {
                                  _selectedLanguage = lang;
                                });
                              },
                            ),

                          const Spacer(flex: 1),

                          // 2. 中央 AI 問題文字區域 (若在評估照片，此文字依然維持在照片上方，完美呼應 image_8be021.png)
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _isLoading
                                ? const QuestionLoadingIndicator()
                                : QuestionArea(questionText: _aiGeneratedText),
                          ),

                          const Spacer(flex: 1),

                          // 3. 動態關鍵字展示區域 (僅在 keywords 擷取狀態下顯示)
                          if (_chatStatus == ChatStatus.keywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              keywords: _extractedKeywords,
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ],

                          // 4. 底部主體控制區
                          // 包含：開始聊天、錄音中、完成、確認生圖、生圖中、評估像不像
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

  /// 核心分流控制：根據狀態回傳對應的子組件
  Widget _buildControlSection() {
    switch (_chatStatus) {
      case ChatStatus.prepare:
        return PrepareView(
          onStartChat: () {
            setState(() {
              _chatStatus = ChatStatus.chatting;
              _recordSeconds = 205;
              _startTimer();
            });
          },
        );
      case ChatStatus.chatting:
        return ListeningView(
          recordSeconds: _recordSeconds,
          onEndRecording: () {
            setState(() {
              _chatStatus = ChatStatus.completed;
              _stopTimer();
            });
          },
        );
      case ChatStatus.completed:
        return CompletedView(
          onRestartChat: () {
            setState(() {
              _chatStatus = ChatStatus.chatting;
              _recordSeconds = 205;
              _startTimer();
            });
          },
          onEndChat: () {
            setState(() {
              _chatStatus = ChatStatus.keywords;
            });
            _fetchKeywordsFromLLM(); // 觸發模擬擷取關鍵字
          },
        );
      case ChatStatus.keywords:
        return KeywordsConfirmButton(
          isDisabled: _isExtractingKeywords,
          onConfirm: _triggerImageGeneration,
        );
      case ChatStatus.generating:
      // 對應 image_8be6e2.png
        return const GeneratingView();
      case ChatStatus.evaluation:
      // 對應 image_8be021.png
        return EvaluationView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: (lang) {
            setState(() {
              _selectedLanguage = lang;
            });
          },
          // 這裡塞入您生成完畢的圖片 URL（此處為精緻的台灣阿嬤灶腳意境圖作為 Placeholder）
          imageUrl: "https://images.unsplash.com/photo-1581579438747-1dc8d1e0ca96?auto=format&fit=crop&q=80&w=600",
          onLike: () {
            // 點選「像」後，可以做資料儲存，隨後返回初始頁面
            _resetAllStates();
          },
          onDislike: () {
            // 點選「不太像」後，可選擇重學生圖或返回初始
            _resetAllStates();
          },
        );
    }
  }
}