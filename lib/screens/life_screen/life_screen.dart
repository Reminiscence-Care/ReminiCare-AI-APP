import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  final LifeScreenController _controller = LifeScreenController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        if (_controller.chatStatus == ChatStatus.chatSummary) return _buildChatSummaryView();

        if (_controller.chatStatus == ChatStatus.introPrepare ||
            _controller.chatStatus == ChatStatus.introRecording ||
            _controller.chatStatus == ChatStatus.introProcessing ||
            _controller.chatStatus == ChatStatus.introNameExtracted ||
            _controller.chatStatus == ChatStatus.introTransition) {
          return _buildIntroView();
        }

        String appBarTitle = _getAppBarTitle();

        final bool isLikeOrDislikeFlow = _controller.chatStatus == ChatStatus.likeChatting ||
            _controller.chatStatus == ChatStatus.dislikeChatting ||
            _controller.chatStatus == ChatStatus.likePrepare ||
            _controller.chatStatus == ChatStatus.dislikePrepare;

        final bool isNextElderOrSummary = _controller.chatStatus == ChatStatus.nextElderPrompt ||
            _controller.chatStatus == ChatStatus.generatingNextTopic ||
            _controller.chatStatus == ChatStatus.roundSummary;

        final bool showImageOnTop = (_controller.chatStatus == ChatStatus.evaluation ||
            isLikeOrDislikeFlow || isNextElderOrSummary) && _controller.currentImageUrl.isNotEmpty;

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
            title: Text(appBarTitle, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
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

                          if (isLikeOrDislikeFlow || isNextElderOrSummary) ...[
                            LanguageSelector(
                              selectedLanguage: _controller.selectedLanguage,
                              onLanguageSelected: (lang) {
                                _controller.selectedLanguage = lang;
                                // 💡 加上 manual 標記，代表是手動點選，只播一次音軌
                                _controller.playCurrentContextVoice(lang, isManualTap: true);
                              },
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                _controller.chatStatus == ChatStatus.nextElderPrompt
                                    ? '${_controller.currentPromptElder}呢？'
                                    : (_controller.chatStatus.toString().contains('dislike') ? '為什麼不像？' : _controller.aiGeneratedText),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          if (showImageOnTop) ...[ _buildEvaluationImage(), const Spacer(flex: 1) ],

                          if (!_isEvaluationState() && !isLikeOrDislikeFlow && !isNextElderOrSummary) ...[
                            LanguageSelector(
                              selectedLanguage: _controller.selectedLanguage,
                              onLanguageSelected: (lang) {
                                _controller.selectedLanguage = lang;
                                // 💡 加上 manual 標記
                                _controller.playCurrentContextVoice(lang, isManualTap: true);
                              },
                            ),
                            const Spacer(flex: 1),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _controller.isLoading
                                  ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                                  : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  QuestionArea(questionText: _controller.aiGeneratedText),
                                  if (_controller.chatStatus == ChatStatus.prepare) ...[
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await _controller.stopAudioSequence();
                                        _controller.fetchInitialQuestion();
                                      },
                                      icon: const Icon(Icons.refresh, size: 20),
                                      label: const Text("換一個問題", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange[50], foregroundColor: Colors.orange[800],
                                          elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Spacer(flex: 1),
                          ],

                          AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _buildControlSection()),

                          if (_controller.isVoiceActiveStatus(_controller.chatStatus) && !isLikeOrDislikeFlow)
                            _buildVoiceAssistantIndicator(),

                          const Spacer(flex: 2),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildChatSummaryView() {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.maybePop(context)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(12)),
                  child: const Text("儲存今天的聊天", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                const SizedBox(height: 40),
                _buildSummaryRow("主題：", _controller.originalKeywords.isNotEmpty ? _controller.originalKeywords.first : "懷舊時光"),
                const SizedBox(height: 24),
                _buildSummaryRow("內容：", _controller.originalKeywords.join("、")),
                const SizedBox(height: 24),
                _buildSummaryRow("分享者：", _controller.elderNames.isNotEmpty ? _controller.elderNames.join("、") : "未留名"),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD54F),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text("下一步", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(16)),
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(value, style: const TextStyle(fontSize: 18, color: Colors.black87)),
            ),
          ),
        ]
    );
  }

  Widget _buildIntroView() {
    if (_controller.chatStatus == ChatStatus.introTransition) {
      return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: const BackButton(color: Colors.black)), body: const Center(child: Text("我們開始聊天！", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87))));
    }
    if (_controller.chatStatus == ChatStatus.introProcessing) {
      return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: const BackButton(color: Colors.black)), body: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.orange), SizedBox(height: 24), Text("正在聆聽長輩的名字...", style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500))])));
    }
    return Scaffold(
      backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: const BackButton(color: Colors.black)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("請大家介紹自己", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Text(_controller.currentElderName.isEmpty ? "我叫________" : "我叫 ${_controller.currentElderName}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
            const SizedBox(height: 60),
            if (_controller.chatStatus == ChatStatus.introPrepare) _buildCircleButton("開始介紹", () => _controller.startIntroRecording())
            else if (_controller.chatStatus == ChatStatus.introRecording) Column(children: [const Text("🗣️ 聆聽中... (說完停頓即可)", style: TextStyle(color: Colors.grey, fontSize: 16)), const SizedBox(height: 16), _buildCircleButton("停止", () => _controller.stopIntroRecordingManually(), color: Colors.redAccent)])
            else if (_controller.chatStatus == ChatStatus.introNameExtracted) Row(mainAxisAlignment: MainAxisAlignment.center, children: [_buildCircleButton("下一位", () => _controller.nextPersonIntro()), const SizedBox(width: 40), _buildCircleButton("結束介紹", () => _controller.finishIntro())]),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton(String text, VoidCallback onPressed, {Color color = const Color(0xFFFFD54F)}) {
    return InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(50), child: Container(width: 100, height: 100, alignment: Alignment.center, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87))));
  }

  bool _isEvaluationState() => _controller.chatStatus == ChatStatus.evaluation || _controller.chatStatus == ChatStatus.dislikeEvaluation || _controller.chatStatus == ChatStatus.dislikePrepare || _controller.chatStatus == ChatStatus.dislikeChatting || _controller.chatStatus == ChatStatus.likePrepare || _controller.chatStatus == ChatStatus.likeChatting;

  String _getAppBarTitle() {
    switch (_controller.chatStatus) {
      case ChatStatus.prepare: case ChatStatus.nextElderPrompt: return "準備聊天";
      case ChatStatus.chatting: return "點開始聊";
      case ChatStatus.generating: case ChatStatus.dislikeGenerating: case ChatStatus.likeGenerating: return "Ai 生圖中";
      case ChatStatus.evaluation: case ChatStatus.dislikeEvaluation: return "問像不像";
      case ChatStatus.dislikePrepare: case ChatStatus.dislikeChatting: return "不像，繼續聊天";
      case ChatStatus.likePrepare: case ChatStatus.likeChatting: return "如果像，就 AI延伸話題";
      case ChatStatus.generatingNextTopic: case ChatStatus.roundSummary: return "延伸新話題";
      default: return "";
    }
  }

  Widget _buildVoiceAssistantIndicator() {
    bool isListeningNow = (_controller.chatStatus == ChatStatus.chatting || _controller.chatStatus == ChatStatus.dislikeChatting || _controller.chatStatus == ChatStatus.likeChatting);
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: isListeningNow ? Colors.red[50] : Colors.green[50], borderRadius: BorderRadius.circular(30), border: Border.all(color: isListeningNow ? Colors.red[200]! : Colors.green[200]!, width: 1)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isListeningNow ? Icons.record_voice_over : Icons.online_prediction_outlined, color: isListeningNow ? Colors.red[700] : Colors.green[700], size: 16),
            const SizedBox(width: 8),
            Text(isListeningNow ? "🎙️ 聆聽中... (記得說「${ReminiCareConfig.endWakeWords.first}」或手動結束)" : "🤖 AI 監聽中... 說「${ReminiCareConfig.startWakeWords.first}」", style: TextStyle(fontSize: 12, color: isListeningNow ? Colors.red[800] : Colors.green[800], fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildEvaluationImage() {
    return Container(
      width: 320, height: 240, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[200]), clipBehavior: Clip.antiAlias,
      child: _controller.currentImageUrl.isNotEmpty
          ? (_controller.currentImageUrl.startsWith('http') || _controller.currentImageUrl.startsWith('https')
          ? Image.network(_controller.currentImageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)), loadingBuilder: (context, child, loadingProgress) { if (loadingProgress == null) return child; return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.grey))); })
          : (kIsWeb ? const Center(child: Text('Web 瀏覽器無法讀取電腦檔案', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13))) : Image.file(File(_controller.currentImageUrl), fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)))))
          : const Center(child: Icon(Icons.image, size: 64, color: Colors.grey)),
    );
  }

  Widget _buildControlSection() {
    switch (_controller.chatStatus) {
      case ChatStatus.prepare: return PrepareView(onStartChat: _controller.triggerStartChatFlow);
      case ChatStatus.chatting: return ListeningView(recordSeconds: _controller.recordSeconds, onEndRecording: _controller.handleEndChat);
      case ChatStatus.generating: return const GeneratingView();

      case ChatStatus.evaluation:
        return EvaluationView(
            selectedLanguage: _controller.selectedLanguage,
            onLanguageSelected: _controller.playCurrentContextVoice,
            onLike: () { _controller.handleLikeAndGenerateExtension(); },
            onDislike: () { _controller.chatStatus = ChatStatus.dislikePrepare; _controller.playCurrentContextVoice(_controller.selectedLanguage); _controller.notifyListeners(); }
        );

      case ChatStatus.likePrepare:
      case ChatStatus.dislikePrepare:
      case ChatStatus.nextElderPrompt:
        return AdvancedPrepareView(onStartChat: _controller.triggerStartChatFlow);

      case ChatStatus.generatingNextTopic:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: 16),
            Text('等待 AI 總結並產生新話題中...', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        );

      case ChatStatus.roundSummary:
        return RoundSummaryControls(
          onContinue: _controller.continueChatFromSummary,
          onFinish: _controller.finishTodayChat,
        );

      case ChatStatus.likeChatting:
      case ChatStatus.dislikeChatting:
        return AdvancedChattingControlView(
            recordSeconds: _controller.recordSeconds,
            onEndRecording: () async { await _controller.handleEndChat(); },
            onCancel: () { Navigator.of(context).popUntil((route) => route.isFirst); }
        );

      case ChatStatus.dislikeGenerating: return const GeneratingView();
      case ChatStatus.likeGenerating: return const GeneratingView();
      default: return const SizedBox();
    }
  }
}