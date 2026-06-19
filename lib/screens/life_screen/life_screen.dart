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

/// 取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
double _getResponsiveFontSize(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  // 假設基準寬度約 400px 時，字體為 24
  double calculatedSize = screenWidth * 0.06;
  return calculatedSize.clamp(24.0, 40.0);
}

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
    double fontSize = _getResponsiveFontSize(context);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        // 🌟 最終回憶卡片
        if (_controller.chatStatus == ChatStatus.chatMemories) return _buildChatMemoriesView(fontSize);

        // 🌟 最終儲存總結卡片
        if (_controller.chatStatus == ChatStatus.chatSummary) return _buildChatSummaryView(fontSize);

        // 🌟 自我介紹階段
        if (_controller.chatStatus == ChatStatus.introPrepare ||
            _controller.chatStatus == ChatStatus.introRecording ||
            _controller.chatStatus == ChatStatus.introProcessing ||
            _controller.chatStatus == ChatStatus.introNameExtracted ||
            _controller.chatStatus == ChatStatus.introTransition) {
          return _buildIntroView(fontSize);
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
                      padding: EdgeInsets.symmetric(horizontal: fontSize, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Spacer(flex: 1),

                          if (isLikeOrDislikeFlow || isNextElderOrSummary) ...[
                            LanguageSelector(
                              selectedLanguage: _controller.selectedLanguage,
                              onLanguageSelected: (lang) {
                                _controller.selectedLanguage = lang;
                                _controller.playCurrentContextVoice(isManualTap: true);
                              },
                            ),
                            SizedBox(height: fontSize * 0.8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                _controller.chatStatus == ChatStatus.nextElderPrompt
                                    ? '${_controller.currentPromptElder}呢？'
                                    : (_controller.chatStatus.toString().contains('dislike') ? '為什麼不像？' : _controller.aiGeneratedText),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: fontSize * 1.1, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ),
                            SizedBox(height: fontSize),
                          ],

                          if (showImageOnTop) ...[ _buildEvaluationImage(fontSize), const Spacer(flex: 1) ],

                          if (!_isEvaluationState() && !isLikeOrDislikeFlow && !isNextElderOrSummary) ...[
                            LanguageSelector(
                              selectedLanguage: _controller.selectedLanguage,
                              onLanguageSelected: (lang) {
                                _controller.selectedLanguage = lang;
                                _controller.playCurrentContextVoice(isManualTap: true);
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
                                    SizedBox(height: fontSize * 0.8),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await _controller.stopAudioSequence();
                                        _controller.fetchInitialQuestion();
                                      },
                                      icon: Icon(Icons.refresh, size: fontSize * 0.9),
                                      label: Text("換一個問題", style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange[50], foregroundColor: Colors.orange[800],
                                          elevation: 0, padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.4)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Spacer(flex: 1),
                          ],

                          AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _buildControlSection()),

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

  Widget _buildChatSummaryView(double fontSize) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.maybePop(context)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800), // 放寬以適應大字體
          child: Container(
            margin: EdgeInsets.all(fontSize),
            padding: EdgeInsets.symmetric(vertical: fontSize * 1.5, horizontal: fontSize),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: SingleChildScrollView( // 加入 ScrollView 避免內容過多溢出
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: fontSize * 1.5, vertical: fontSize * 0.6),
                    decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(12)),
                    child: Text("儲存今天的聊天", style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  SizedBox(height: fontSize * 1.5),
                  _buildSummaryRow("主題：", _controller.originalKeywords.isNotEmpty ? _controller.originalKeywords.first : "懷舊時光", fontSize),
                  SizedBox(height: fontSize),
                  _buildSummaryRow("內容：", _controller.originalKeywords.join("、"), fontSize),
                  SizedBox(height: fontSize),
                  _buildSummaryRow("分享者：", _controller.elderNames.isNotEmpty ? _controller.elderNames.join("、") : "未留名", fontSize),
                  SizedBox(height: fontSize * 2),
                  ElevatedButton(
                    onPressed: () => _controller.saveAndShowMemories(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD54F),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: EdgeInsets.symmetric(horizontal: fontSize * 2, vertical: fontSize * 0.6),
                      elevation: 0,
                    ),
                    child: Text("下一步", style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, double fontSize) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            // 移除固定寬度，改用 padding 和約束
            constraints: BoxConstraints(minWidth: fontSize * 4),
            padding: EdgeInsets.symmetric(horizontal: fontSize * 0.6, vertical: fontSize * 0.4),
            decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(16)),
            child: Text(label, style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
          SizedBox(width: fontSize * 0.8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: fontSize * 0.3),
              child: Text(value, style: TextStyle(fontSize: fontSize * 0.9, color: Colors.black87)),
            ),
          ),
        ]
    );
  }

  // ==========================================
  // 🌟 新增：今天聊天的回憶卡片 (儲存後展示)
  // ==========================================
  Widget _buildChatMemoriesView(double fontSize) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000), // 放寬以適應大字體和並排
          child: Container(
            margin: EdgeInsets.all(fontSize),
            padding: EdgeInsets.symmetric(vertical: fontSize * 1.5, horizontal: fontSize * 1.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: fontSize * 2, vertical: fontSize * 0.6),
                    decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(12)),
                    child: Text("今天聊天的回憶", style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  SizedBox(height: fontSize * 1.5),
                  // 使用 Wrap 讓左側文字和右側圖片在小螢幕時能自動換行
                  Wrap(
                    spacing: fontSize * 1.5,
                    runSpacing: fontSize * 1.5,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // 左側：文字資訊
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          children: [
                            _buildSummaryRow("主題：", _controller.originalKeywords.isNotEmpty ? _controller.originalKeywords.first : "懷舊時光", fontSize),
                            SizedBox(height: fontSize),
                            _buildSummaryRow("內容：", _controller.originalKeywords.join("、"), fontSize),
                            SizedBox(height: fontSize),
                            _buildSummaryRow("分享者：", _controller.elderNames.isNotEmpty ? _controller.elderNames.join("、") : "未留名", fontSize),
                          ],
                        ),
                      ),
                      // 右側：AI 生成的圖片
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: AspectRatio(
                          aspectRatio: 4 / 3, // 保持圖片比例
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[200],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _controller.currentImageUrl.isNotEmpty
                                ? (_controller.currentImageUrl.startsWith('http') || _controller.currentImageUrl.startsWith('https')
                                ? Image.network(_controller.currentImageUrl, fit: BoxFit.cover)
                                : (kIsWeb ? const Center(child: Text('Web 無法預覽', style: TextStyle(color: Colors.grey))) : Image.file(File(_controller.currentImageUrl), fit: BoxFit.cover)))
                                : Center(child: Icon(Icons.image, size: fontSize * 2, color: Colors.grey)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: fontSize * 2),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD54F),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: EdgeInsets.symmetric(horizontal: fontSize * 2.5, vertical: fontSize * 0.6),
                      elevation: 0,
                    ),
                    child: Text("結束", style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 👥 自我介紹系列視圖
  // ==========================================
  Widget _buildIntroView(double fontSize) {
    if (_controller.chatStatus == ChatStatus.introTransition) {
      return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: const BackButton(color: Colors.black)), body: Center(child: Text("我們開始聊天！", style: TextStyle(fontSize: fontSize * 1.2, fontWeight: FontWeight.bold, color: Colors.black87))));
    }
    if (_controller.chatStatus == ChatStatus.introProcessing) {
      return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: const BackButton(color: Colors.black)), body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(color: Colors.orange), SizedBox(height: fontSize), Text("正在聆聽長輩的名字...", style: TextStyle(fontSize: fontSize * 0.8, color: Colors.grey, fontWeight: FontWeight.w500))])));
    }
    return Scaffold(
      backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: const BackButton(color: Colors.black)),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("請大家介紹自己", style: TextStyle(fontSize: fontSize * 1.2, fontWeight: FontWeight.bold)),
              SizedBox(height: fontSize * 1.5),
              Text(_controller.currentElderName.isEmpty ? "我叫________" : "我叫 ${_controller.currentElderName}", style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500)),
              SizedBox(height: fontSize * 2.5),
              if (_controller.chatStatus == ChatStatus.introPrepare) _buildCircleButton("開始介紹", () => _controller.startIntroRecording(), fontSize)
              else if (_controller.chatStatus == ChatStatus.introRecording) Column(children: [Text("🗣️ 聆聽中... (說完停頓即可)", style: TextStyle(color: Colors.grey, fontSize: fontSize * 0.8)), SizedBox(height: fontSize * 0.8), _buildCircleButton("停止", () => _controller.stopIntroRecordingManually(), fontSize, color: Colors.redAccent)])
              else if (_controller.chatStatus == ChatStatus.introNameExtracted) Wrap(alignment: WrapAlignment.center, spacing: fontSize * 1.5, runSpacing: fontSize, children: [_buildCircleButton("下一位", () => _controller.nextPersonIntro(), fontSize), _buildCircleButton("結束介紹", () => _controller.finishIntro(), fontSize)]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton(String text, VoidCallback onPressed, double fontSize, {Color color = const Color(0xFFFFD54F)}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        // 使用 padding 和 minConstraints 取代固定寬高
        constraints: BoxConstraints(minWidth: fontSize * 4, minHeight: fontSize * 4),
        padding: EdgeInsets.all(fontSize * 0.8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(text, style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold, color: Colors.black87), textAlign: TextAlign.center),
      ),
    );
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

  Widget _buildEvaluationImage(double fontSize) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800), // 限制圖片最大寬度
      child: AspectRatio(
        aspectRatio: 4 / 3, // 保持圖片比例
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[200]),
          clipBehavior: Clip.antiAlias,
          child: _controller.currentImageUrl.isNotEmpty
              ? (_controller.currentImageUrl.startsWith('http') || _controller.currentImageUrl.startsWith('https')
              ? Image.network(_controller.currentImageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, size: fontSize * 2.5, color: Colors.grey)), loadingBuilder: (context, child, loadingProgress) { if (loadingProgress == null) return child; return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.grey))); })
              : (kIsWeb ? Center(child: Text('Web 瀏覽器無法讀取電腦檔案', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: fontSize * 0.6))) : Image.file(File(_controller.currentImageUrl), fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, size: fontSize * 2.5, color: Colors.grey)))))
              : Center(child: Icon(Icons.image, size: fontSize * 2.5, color: Colors.grey)),
        ),
      ),
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
            onLanguageSelected: (lang) {
              _controller.selectedLanguage = lang;
              _controller.playCurrentContextVoice(isManualTap: true);
            },
            onLike: () { _controller.handleLikeAndGenerateExtension(); },
            onDislike: () {
              _controller.chatStatus = ChatStatus.dislikePrepare;
              _controller.playCurrentContextVoice();
            }
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
            Text('等待 AI 總結並產生新問題中...', style: TextStyle(fontSize: 16, color: Colors.grey)),
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