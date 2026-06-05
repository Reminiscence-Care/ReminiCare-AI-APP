import 'dart:async';
import 'package:flutter/material.dart';

// 匯入拆分到 widgets 資料夾底下的自定義組件
import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/keywords_view.dart';
import 'widgets/generating_overlay.dart';

/// 聊天流程的四個狀態：準備中、進行/聆聽中、完成、關鍵詞擷取
enum ChatStatus {
  prepare,
  chatting,
  completed,
  keywords,
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
  bool _isGeneratingImage = false;

  int _recordSeconds = 205; // 預設 03:25
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
  // 模擬異步 LLM API 呼叫 (LLM / AI Mocking)
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

  Future<void> _triggerImageGeneration() async {
    setState(() {
      _isGeneratingImage = true;
    });
    // TODO: 串接您的生圖 API
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _isGeneratingImage = false;
    });
    _resetAllStates();
  }

  // ==========================================
  // 主畫面排版 (Main Build Method)
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: '重新生成問題',
            onPressed: (_isLoading || _chatStatus != ChatStatus.prepare)
                ? null
                : _fetchQuestionFromLLM,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // 1. 語言選擇器
                  LanguageSelector(
                    selectedLanguage: _selectedLanguage,
                    onLanguageSelected: (lang) {
                      setState(() {
                        _selectedLanguage = lang;
                      });
                    },
                  ),

                  const Spacer(flex: 2),

                  // 2. 中央問題顯示區
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isLoading
                        ? const QuestionLoadingIndicator()
                        : QuestionArea(questionText: _aiGeneratedText),
                  ),

                  const Spacer(flex: 2),

                  // 3. 關鍵字擷取顯示區 (僅在 keywords 狀態顯示)
                  if (_chatStatus == ChatStatus.keywords)
                    KeywordsView(
                      isLoading: _isExtractingKeywords,
                      keywords: _extractedKeywords,
                      maxLength: _maxKeywordLength,
                    ),

                  const Spacer(flex: 2),

                  // 4. 底部動態控制區
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildControlSection(),
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),

            // 5. 生圖覆蓋遮罩
            if (_isGeneratingImage) const GeneratingOverlay(),
          ],
        ),
      ),
    );
  }

  /// 根據當前狀態分流調度不同的子元件
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
            _fetchKeywordsFromLLM(); // 觸發關鍵詞擷取
          },
        );
      case ChatStatus.keywords:
        return KeywordsConfirmButton(
          isDisabled: _isExtractingKeywords,
          onConfirm: _triggerImageGeneration,
        );
    }
  }
}