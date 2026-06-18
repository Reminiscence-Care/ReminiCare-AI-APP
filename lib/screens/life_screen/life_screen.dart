import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';

import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/keywords_view.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';

// =========================================================================
// 🎨 LifeScreen: 純粹的外觀層 (View)，透過 ListenableBuilder 綁定 Controller
// =========================================================================
class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  // 💡 實例化大腦 (Controller)
  late final LifeScreenController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LifeScreenController();
    _controller.init(); // 啟動所有邏輯
  }

  @override
  void dispose() {
    _controller.dispose(); // 釋放記憶體與硬體鎖
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 💡 ListenableBuilder 會在 _controller 呼叫 notifyListeners() 時自動重繪畫面！
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final chatStatus = _controller.chatStatus;

        String appBarTitle = _getAppBarTitle(chatStatus);
        final bool showImageOnTop = _shouldShowImageOnTop(chatStatus);

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () => Navigator.maybePop(context),
            ),
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

                              // --- 語音語言選擇器 ---
                              if (chatStatus != ChatStatus.evaluation && chatStatus != ChatStatus.dislikePrepare &&
                                  chatStatus != ChatStatus.dislikeChatting && chatStatus != ChatStatus.likePrepare &&
                                  chatStatus != ChatStatus.likeChatting && chatStatus != ChatStatus.dislikeEvaluation) ...[
                                LanguageSelector(
                                  selectedLanguage: _controller.selectedLanguage,
                                  onLanguageSelected: _controller.playCurrentContextVoice,
                                ),
                                const Spacer(flex: 1),
                              ],

                              // --- AI 提問區域 ---
                              if (chatStatus != ChatStatus.evaluation && chatStatus != ChatStatus.dislikeEvaluation &&
                                  chatStatus != ChatStatus.dislikePrepare && chatStatus != ChatStatus.dislikeChatting &&
                                  chatStatus != ChatStatus.likePrepare && chatStatus != ChatStatus.likeChatting) ...[
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: _controller.isLoading
                                      ? const QuestionLoadingIndicator()
                                      : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      QuestionArea(questionText: _controller.aiGeneratedText),
                                      if (chatStatus == ChatStatus.prepare) ...[
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          onPressed: () async {
                                            await _controller.stopAudioSequence();
                                            _controller.fetchInitialQuestion();
                                          },
                                          icon: const Icon(Icons.refresh, size: 20),
                                          label: const Text("換一個問題", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.orange[50],
                                              foregroundColor: Colors.orange[800],
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                                side: BorderSide(color: Colors.orange[200]!),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Spacer(flex: 1),
                              ],

                              // --- 關鍵字擷取區域 ---
                              if (chatStatus == ChatStatus.keywords) ...[
                                KeywordsView(
                                  isLoading: _controller.isExtractingKeywords,
                                  originalKeywords: _controller.originalKeywords,
                                  newKeywords: const [],
                                  maxLength: _controller.maxKeywordLength,
                                ),
                                const Spacer(flex: 1),
                              ] else if (chatStatus == ChatStatus.dislikeKeywords || chatStatus == ChatStatus.likeKeywords) ...[
                                KeywordsView(
                                  isLoading: _controller.isExtractingKeywords,
                                  originalKeywords: _controller.originalKeywords,
                                  newKeywords: _controller.newKeywords,
                                  maxLength: _controller.maxKeywordLength,
                                ),
                                const Spacer(flex: 1),
                              ],

                              // --- 動態操作按鈕區域 ---
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: _buildControlSection(),
                              ),

                              // --- AI 監聽指示器 ---
                              if (_controller.isVoiceActiveStatus())
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
      },
    );
  }

  String _getAppBarTitle(ChatStatus status) {
    switch (status) {
      case ChatStatus.prepare: return "準備聊天";
      case ChatStatus.chatting:
      case ChatStatus.completed: return "點開始聊";
      case ChatStatus.keywords: return "抓取關鍵詞";
      case ChatStatus.generating:
      case ChatStatus.dislikeGenerating:
      case ChatStatus.likeGenerating: return "Ai 生圖中";
      case ChatStatus.evaluation:
      case ChatStatus.dislikeEvaluation: return "問像不像";
      case ChatStatus.dislikePrepare:
      case ChatStatus.dislikeChatting:
      case ChatStatus.dislikeCompleted:
      case ChatStatus.dislikeKeywords: return "不像，繼續聊天";
      case ChatStatus.likePrepare:
      case ChatStatus.likeChatting:
      case ChatStatus.likeCompleted:
      case ChatStatus.likeKeywords: return "如果像，就 AI延伸話題";
    }
  }

  bool _shouldShowImageOnTop(ChatStatus status) {
    return status == ChatStatus.evaluation ||
        status == ChatStatus.dislikePrepare || status == ChatStatus.dislikeChatting ||
        status == ChatStatus.dislikeCompleted || status == ChatStatus.dislikeKeywords ||
        status == ChatStatus.dislikeEvaluation || status == ChatStatus.likePrepare ||
        status == ChatStatus.likeChatting || status == ChatStatus.likeCompleted ||
        status == ChatStatus.likeKeywords;
  }

  Widget _buildVoiceAssistantIndicator() {
    final status = _controller.chatStatus;
    bool isListeningNow = (status == ChatStatus.chatting || status == ChatStatus.dislikeChatting || status == ChatStatus.likeChatting);
    bool isCompletedState = (status == ChatStatus.completed || status == ChatStatus.dislikeCompleted || status == ChatStatus.likeCompleted);

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isListeningNow ? Colors.red[50] : Colors.green[50],
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isListeningNow ? Colors.red[200]! : Colors.green[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isListeningNow ? Icons.record_voice_over : Icons.online_prediction_outlined,
              color: isListeningNow ? Colors.red[700] : Colors.green[700],
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              isListeningNow
                  ? "🎙️ 聆聽中... (記得說「${ReminiCareConfig.endWakeWords.first}」或手動結束)"
                  : isCompletedState
                  ? "🤖 AI 監聽中... 說「${ReminiCareConfig.restartWakeWords.first}」或「${ReminiCareConfig.endWakeWords.first}」"
                  : "🤖 AI 監聽中... 說「${ReminiCareConfig.startWakeWords.first}」",
              style: TextStyle(
                fontSize: 12,
                color: isListeningNow ? Colors.red[800] : Colors.green[800],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvaluationImage() {
    final imageUrl = _controller.currentImageUrl;
    return Container(
      width: 320,
      height: 240,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[200]),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? (imageUrl.startsWith('http') || imageUrl.startsWith('https')
          ? Image.network(
        imageUrl, fit: BoxFit.cover,
        errorBuilder: (ctx, error, st) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
        loadingBuilder: (ctx, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
      )
          : (kIsWeb
          ? const Center(child: Text('Web 無法讀取硬碟', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
          : Image.file(
        File(imageUrl), fit: BoxFit.cover,
        errorBuilder: (ctx, error, st) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
      )))
          : const Center(child: Icon(Icons.image, size: 64, color: Colors.grey)),
    );
  }

  Widget _buildControlSection() {
    switch (_controller.chatStatus) {
      case ChatStatus.prepare:
        return PrepareView(onStartChat: _controller.triggerStartChatFlow);
      case ChatStatus.chatting:
        return ListeningView(recordSeconds: _controller.recordSeconds, onEndRecording: _controller.handleEndChat);
      case ChatStatus.completed:
        return CompletedView(
          onRestartChat: _controller.triggerStartChatFlow,
          onEndChat: () async {
            await _controller.stopAudioSequence();
            _controller.setChatStatusAndNotify(ChatStatus.keywords);
            await _controller.voiceManager.stopActiveAudioOperations();
          },
        );
      case ChatStatus.keywords:
        return KeywordsConfirmButton(isDisabled: _controller.isExtractingKeywords, onConfirm: _controller.triggerImageGeneration);
      case ChatStatus.generating:
      case ChatStatus.dislikeGenerating:
      case ChatStatus.likeGenerating:
        return const GeneratingView();
      case ChatStatus.evaluation:
        return EvaluationView(
          selectedLanguage: _controller.selectedLanguage,
          onLanguageSelected: _controller.playCurrentContextVoice,
          onLike: () {
            _controller.setChatStatusAndNotify(ChatStatus.likePrepare);
            _controller.voiceManager.checkCompletedCommands = false;
            _controller.voiceManager.startBackgroundWakeWordCycle();
            _controller.playCurrentContextVoice(_controller.selectedLanguage); // trigger sequence play indirectly
          },
          onDislike: () {
            _controller.setChatStatusAndNotify(ChatStatus.dislikePrepare);
            _controller.voiceManager.checkCompletedCommands = false;
            _controller.voiceManager.startBackgroundWakeWordCycle();
            _controller.playCurrentContextVoice(_controller.selectedLanguage);
          },
        );
      case ChatStatus.dislikePrepare:
        return DislikePrepareView(
          selectedLanguage: _controller.selectedLanguage,
          onLanguageSelected: _controller.playCurrentContextVoice,
          onStartChat: _controller.triggerStartChatFlow,
        );
      case ChatStatus.dislikeChatting:
        return DislikeChattingView(
          selectedLanguage: _controller.selectedLanguage,
          onLanguageSelected: _controller.playCurrentContextVoice,
          recordSeconds: _controller.recordSeconds,
          onEndRecording: _controller.handleEndChat,
        );
      case ChatStatus.dislikeCompleted:
        return CompletedView(
          onRestartChat: _controller.triggerStartChatFlow,
          onEndChat: () async {
            await _controller.stopAudioSequence();
            _controller.setChatStatusAndNotify(ChatStatus.dislikeKeywords);
            await _controller.voiceManager.stopActiveAudioOperations();
          },
        );
      case ChatStatus.dislikeKeywords:
        return KeywordsConfirmButton(isDisabled: _controller.isExtractingKeywords, onConfirm: _controller.triggerModifiedImageGeneration);
      case ChatStatus.dislikeEvaluation:
        return DislikeEvaluationView(
          onContinueModify: () {
            _controller.setChatStatusAndNotify(ChatStatus.dislikePrepare);
            _controller.voiceManager.checkCompletedCommands = false;
            _controller.voiceManager.startBackgroundWakeWordCycle();
            _controller.playCurrentContextVoice(_controller.selectedLanguage);
          },
          onFinished: _controller.resetAllStates,
        );
      case ChatStatus.likePrepare:
        return LikePrepareView(
          selectedLanguage: _controller.selectedLanguage,
          onLanguageSelected: _controller.playCurrentContextVoice,
          onStartChat: _controller.triggerStartChatFlow,
        );
      case ChatStatus.likeChatting:
        return LikeChattingView(
          selectedLanguage: _controller.selectedLanguage,
          onLanguageSelected: _controller.playCurrentContextVoice,
          recordSeconds: _controller.recordSeconds,
          onEndRecording: _controller.handleEndChat,
        );
      case ChatStatus.likeCompleted:
        return CompletedView(
          onRestartChat: _controller.triggerStartChatFlow,
          onEndChat: () async {
            await _controller.stopAudioSequence();
            _controller.setChatStatusAndNotify(ChatStatus.likeKeywords);
            await _controller.voiceManager.stopActiveAudioOperations();
          },
        );
      case ChatStatus.likeKeywords:
        return KeywordsConfirmButton(isDisabled: _controller.isExtractingKeywords, onConfirm: _controller.triggerLikeExtendedImageGeneration);
    }
  }
}