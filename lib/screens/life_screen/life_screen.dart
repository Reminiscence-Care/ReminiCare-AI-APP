import 'dart:async';
import 'package:flutter/material.dart';

// 模組化組件相對路徑匯入
import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/keywords_view.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';

/// 聊天與修改、AI延伸話題流程的完整狀態機
enum ChatStatus {
  prepare,
  chatting,
  completed,
  keywords,
  generating,
  evaluation,
  dislikePrepare,
  dislikeChatting,
  dislikeCompleted,
  dislikeKeywords,
  dislikeGenerating,
  dislikeEvaluation,
  likePrepare,       // 新增：按下「像」之後，詢問「這張圖片讓您想到什麼？」的準備狀態
  likeChatting,      // 新增：這張圖片讓您想到什麼？的錄音中狀態
  likeCompleted,     // 新增：這張圖片讓您想到什麼？的錄音結束狀態
  likeKeywords,      // 新增：這張圖片讓您想到什麼？的關鍵詞擷取狀態
  likeGenerating,    // 新增：這張圖片讓您想到什麼？的 AI 生圖中狀態
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

  // 基礎關鍵字 (白底細框)
  final List<String> _originalKeywords = ["蕃薯飯", "豆乾"];
  // 「不太像」新增的修改關鍵字 (灰底)
  final List<String> _newKeywords = ["蕃薯粥", "磨骨豆乾"];
  // 「像」延伸話題新增的關鍵字 (灰底 - 摸魚, 兄弟姊妹, 山上)
  final List<String> _likeOriginalKeywords = ["摸魚", "山上"];
  final List<String> _likeNewKeywords = ["兄弟姊妹"];

  // 意境展示圖片
  String _currentImageUrl = "https://images.unsplash.com/photo-1581579438747-1dc8d1e0ca96?auto=format&fit=crop&q=80&w=600"; // 阿嬤灶腳
  final String _dislikeImageUrl = "https://images.unsplash.com/photo-1604152135912-04a022e23696?auto=format&fit=crop&q=80&w=600"; // 不太像：蕃薯粥與小菜
  final String _likeExtendedImageUrl = "https://images.unsplash.com/photo-1543157148-f68f214f1129?auto=format&fit=crop&q=80&w=600"; // 像：兄弟姊妹在山上與古早廚房意境

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
      _currentImageUrl = "https://images.unsplash.com/photo-1581579438747-1dc8d1e0ca96?auto=format&fit=crop&q=80&w=600";
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
      await Future.delayed(const Duration(milliseconds: 1500));
      setState(() {
        _isExtractingKeywords = false;
      });
    } catch (e) {
      setState(() {
        _isExtractingKeywords = false;
      });
    }
  }

  /// 第一次確認生圖流程
  Future<void> _triggerImageGeneration() async {
    setState(() {
      _chatStatus = ChatStatus.generating;
    });
    await Future.delayed(const Duration(seconds: 3));
    setState(() {
      _chatStatus = ChatStatus.evaluation;
    });
  }

  /// 「不太像」確認生圖流程 (修改圖)
  Future<void> _triggerModifiedImageGeneration() async {
    setState(() {
      _chatStatus = ChatStatus.dislikeGenerating;
    });
    await Future.delayed(const Duration(seconds: 3));
    setState(() {
      _currentImageUrl = _dislikeImageUrl; // 替換為不滿意修改後的圖片
      _chatStatus = ChatStatus.dislikeEvaluation;
    });
  }

  /// 「像」延伸話題確認生圖流程 (新生圖)
  Future<void> _triggerLikeExtendedImageGeneration() async {
    setState(() {
      _chatStatus = ChatStatus.likeGenerating;
    });
    await Future.delayed(const Duration(seconds: 3));
    setState(() {
      _currentImageUrl = _likeExtendedImageUrl; // 替換為像/延伸話題生出的新回憶照片
      _chatStatus = ChatStatus.evaluation; // 自動跳回去之前問像不像的頁面
    });
  }

  // ==========================================
  // 主畫面排版 (Main Build Method)
  // ==========================================
  @override
  Widget build(BuildContext context) {
    // 依狀態改變 AppBar 頂部標籤
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
      case ChatStatus.dislikeGenerating:
      case ChatStatus.likeGenerating:
        appBarTitle = "Ai 生圖中";
        break;
      case ChatStatus.evaluation:
      case ChatStatus.dislikeEvaluation:
        appBarTitle = "問像不像";
        break;
      case ChatStatus.dislikePrepare:
      case ChatStatus.dislikeChatting:
      case ChatStatus.dislikeCompleted:
      case ChatStatus.dislikeKeywords:
        appBarTitle = "不像，繼續聊天";
        break;
      case ChatStatus.likePrepare:
      case ChatStatus.likeChatting:
      case ChatStatus.likeCompleted:
      case ChatStatus.likeKeywords:
        appBarTitle = "如果像，就 AI延伸話題";
        break;
    }

    // 檢查是否處於需要顯示大照片的狀態 (生圖載入中不顯示舊照片，展示乾淨的三點 Loading 或灰色 card)
    final bool showImageOnTop = _chatStatus == ChatStatus.evaluation ||
        _chatStatus == ChatStatus.dislikePrepare ||
        _chatStatus == ChatStatus.dislikeChatting ||
        _chatStatus == ChatStatus.dislikeCompleted ||
        _chatStatus == ChatStatus.dislikeKeywords ||
        _chatStatus == ChatStatus.dislikeEvaluation ||
        _chatStatus == ChatStatus.likePrepare ||
        _chatStatus == ChatStatus.likeChatting ||
        _chatStatus == ChatStatus.likeCompleted ||
        _chatStatus == ChatStatus.likeKeywords;

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
          if (_chatStatus == ChatStatus.prepare)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.grey),
              tooltip: '重新生成問題',
              onPressed: _isLoading ? null : _fetchQuestionFromLLM,
            ),
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

                          // A. 照片展示狀態置頂
                          if (showImageOnTop) ...[
                            _buildEvaluationImage(),
                            const Spacer(flex: 1),
                          ],

                          // B. 頂部語言選擇器 (水平)
                          // 注意：在評價與部分垂直擺放狀態下需隱藏
                          if (_chatStatus != ChatStatus.evaluation &&
                              _chatStatus != ChatStatus.dislikePrepare &&
                              _chatStatus != ChatStatus.dislikeChatting &&
                              _chatStatus != ChatStatus.likePrepare &&
                              _chatStatus != ChatStatus.likeChatting &&
                              _chatStatus != ChatStatus.dislikeEvaluation) ...[
                            LanguageSelector(
                              selectedLanguage: _selectedLanguage,
                              onLanguageSelected: (lang) => setState(() => _selectedLanguage = lang),
                            ),
                            const Spacer(flex: 1),
                          ],

                          // C. 中央 AI 問題與說明文字區域
                          if (_chatStatus != ChatStatus.evaluation &&
                              _chatStatus != ChatStatus.dislikeEvaluation &&
                              _chatStatus != ChatStatus.dislikePrepare &&
                              _chatStatus != ChatStatus.dislikeChatting &&
                              _chatStatus != ChatStatus.likePrepare &&
                              _chatStatus != ChatStatus.likeChatting) ...[
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isLoading
                                  ? const QuestionLoadingIndicator()
                                  : QuestionArea(questionText: _aiGeneratedText),
                            ),
                            const Spacer(flex: 1),
                          ],

                          // D. 關鍵字展示區 (配合狀態渲染白底/灰底標籤)
                          if (_chatStatus == ChatStatus.keywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: const [],
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ] else if (_chatStatus == ChatStatus.dislikeKeywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: _newKeywords,
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ] else if (_chatStatus == ChatStatus.likeKeywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _likeOriginalKeywords,
                              newKeywords: _likeNewKeywords, // 灰色格為新的提示 (兄弟姊妹)
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ],

                          // E. 底部主體控制分流
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

  /// 頂部意境照片展示組件
  Widget _buildEvaluationImage() {
    return Container(
      width: 320,
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        _currentImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
            ),
          );
        },
      ),
    );
  }

  /// 核心分流控制，調度對應子組件
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
            _fetchKeywordsFromLLM();
          },
        );
      case ChatStatus.keywords:
        return KeywordsConfirmButton(
          isDisabled: _isExtractingKeywords,
          onConfirm: _triggerImageGeneration,
        );
      case ChatStatus.generating:
        return const GeneratingView();
      case ChatStatus.evaluation:
        return EvaluationView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: (lang) => setState(() => _selectedLanguage = lang),
          onLike: () {
            setState(() {
              _chatStatus = ChatStatus.likePrepare; // 按下「像」進入延伸話題修改流 (image_697640)
            });
          },
          onDislike: () {
            setState(() {
              _chatStatus = ChatStatus.dislikePrepare; // 按下「不太像」進入不滿意修改流 (image_69eb18)
            });
          },
        );

    // ==========================================
    // 「不太像」不滿意二次微調流程 (dislike flow)
    // ==========================================
      case ChatStatus.dislikePrepare:
        return DislikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: (lang) => setState(() => _selectedLanguage = lang),
          onStartChat: () {
            setState(() {
              _chatStatus = ChatStatus.dislikeChatting;
              _recordSeconds = 205;
              _startTimer();
            });
          },
        );
      case ChatStatus.dislikeChatting:
        return DislikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: (lang) => setState(() => _selectedLanguage = lang),
          recordSeconds: _recordSeconds,
          onEndRecording: () {
            setState(() {
              _chatStatus = ChatStatus.dislikeCompleted;
              _stopTimer();
            });
          },
        );
      case ChatStatus.dislikeCompleted:
        return CompletedView(
          onRestartChat: () {
            setState(() {
              _chatStatus = ChatStatus.dislikeChatting;
              _recordSeconds = 205;
              _startTimer();
            });
          },
          onEndChat: () {
            setState(() {
              _chatStatus = ChatStatus.dislikeKeywords;
            });
            _fetchKeywordsFromLLM();
          },
        );
      case ChatStatus.dislikeKeywords:
        return KeywordsConfirmButton(
          isDisabled: _isExtractingKeywords,
          onConfirm: _triggerModifiedImageGeneration,
        );
      case ChatStatus.dislikeGenerating:
        return const GeneratingView();
      case ChatStatus.dislikeEvaluation:
        return DislikeEvaluationView(
          onContinueModify: () {
            setState(() {
              _chatStatus = ChatStatus.dislikePrepare;
            });
          },
          onFinished: _resetAllStates,
        );

    // ==========================================
    // 「像」延伸話題流程 (like flow - 新增)
    // ==========================================
      case ChatStatus.likePrepare:
        return LikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: (lang) => setState(() => _selectedLanguage = lang),
          onStartChat: () {
            setState(() {
              _chatStatus = ChatStatus.likeChatting;
              _recordSeconds = 205;
              _startTimer();
            });
          },
        );
      case ChatStatus.likeChatting:
        return LikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: (lang) => setState(() => _selectedLanguage = lang),
          recordSeconds: _recordSeconds,
          onEndRecording: () {
            setState(() {
              _chatStatus = ChatStatus.likeCompleted;
              _stopTimer();
            });
          },
        );
      case ChatStatus.likeCompleted:
        return CompletedView(
          onRestartChat: () {
            setState(() {
              _chatStatus = ChatStatus.likeChatting;
              _recordSeconds = 205;
              _startTimer();
            });
          },
          onEndChat: () {
            setState(() {
              _chatStatus = ChatStatus.likeKeywords;
            });
            _fetchKeywordsFromLLM();
          },
        );
      case ChatStatus.likeKeywords:
        return KeywordsConfirmButton(
          isDisabled: _isExtractingKeywords,
          onConfirm: _triggerLikeExtendedImageGeneration,
        );
      case ChatStatus.likeGenerating:
        return const GeneratingView();
    }
  }
}