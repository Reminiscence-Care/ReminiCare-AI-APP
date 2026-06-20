import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';

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

  /// 🌟 共用：取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
  double _getResponsiveFontSize(BuildContext context) {
    double screenWidth = MediaQuery.sizeOf(context).width;
    double calculatedSize = screenWidth * 0.06;
    return calculatedSize.clamp(24.0, 40.0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        // 🌟 最終回憶卡片
        if (_controller.chatStatus == ChatStatus.chatMemories) return _buildChatMemoriesView();

        // 🌟 最終儲存總結卡片
        if (_controller.chatStatus == ChatStatus.chatSummary) return _buildChatSummaryView();

        // 🌟 自我介紹階段
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

        double fontSize = _getResponsiveFontSize(context);

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
            // AppBar 標題也可以稍微放大，但通常不超過 28
            title: Text(appBarTitle, style: TextStyle(color: Colors.black, fontSize: fontSize * 0.8, fontWeight: FontWeight.bold)),
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.8, vertical: fontSize * 0.5),
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
                            SizedBox(height: fontSize * 0.5),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                _controller.chatStatus == ChatStatus.nextElderPrompt
                                    ? '${_controller.currentPromptElder}呢？'
                                    : (_controller.chatStatus.toString().contains('dislike') ? '為什麼不像？' : _controller.fullQuestionText),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ),
                            SizedBox(height: fontSize * 0.8),
                          ],

                          if (showImageOnTop) ...[ _buildEvaluationImage(), const Spacer(flex: 1) ],

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
                                  ? const QuestionLoadingIndicator()
                                  : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  QuestionArea(
                                    mainText: _controller.currentMainQuestion,
                                    subText: _controller.currentSubQuestion,
                                  ),
                                  if (_controller.chatStatus == ChatStatus.prepare) ...[
                                    SizedBox(height: fontSize * 0.6),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await _controller.stopAudioSequence();
                                        _controller.fetchInitialQuestion();
                                      },
                                      icon: Icon(Icons.refresh, size: fontSize * 0.8),
                                      label: Text("換一個問題", style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange[50], foregroundColor: Colors.orange[800],
                                          elevation: 0, padding: EdgeInsets.symmetric(horizontal: fontSize * 0.8, vertical: fontSize * 0.4)),
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

  // ==========================================
  // 🌟 動態比例的生圖展示區塊
  // ==========================================
  Widget _buildEvaluationImage() {
    double screenWidth = MediaQuery.sizeOf(context).width;
    // 圖片寬度最大不超過 600，且隨螢幕縮放
    double imgWidth = (screenWidth * 0.7).clamp(280.0, 600.0);
    double imgHeight = imgWidth * 0.75; // 維持 4:3 比例

    return Container(
      width: imgWidth, height: imgHeight,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.grey[200]),
      clipBehavior: Clip.antiAlias,
      child: _controller.currentImageUrl.isNotEmpty
          ? (_controller.currentImageUrl.startsWith('http') || _controller.currentImageUrl.startsWith('https')
          ? Image.network(_controller.currentImageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, size: imgWidth * 0.2, color: Colors.grey)), loadingBuilder: (context, child, loadingProgress) { if (loadingProgress == null) return child; return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.grey))); })
          : (kIsWeb ? Center(child: Text('Web 無法預覽', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: _getResponsiveFontSize(context) * 0.6))) : Image.file(File(_controller.currentImageUrl), fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, size: imgWidth * 0.2, color: Colors.grey)))))
          : Center(child: Icon(Icons.image, size: imgWidth * 0.2, color: Colors.grey)),
    );
  }

  // ==========================================
  // 🌟 最終儲存總結卡片 (動態縮放 + Wrap 防止爆版)
  // ==========================================
  Widget _buildChatSummaryView() {
    double fontSize = _getResponsiveFontSize(context);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Colors.black, size: fontSize), onPressed: () => Navigator.maybePop(context)),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Container(
              margin: EdgeInsets.all(fontSize),
              padding: EdgeInsets.symmetric(vertical: fontSize * 1.5, horizontal: fontSize),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.5),
                    decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(16)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fontSize)),
                      padding: EdgeInsets.symmetric(horizontal: fontSize * 2, vertical: fontSize * 0.6),
                      elevation: 0,
                    ),
                    child: Text("下一步", style: TextStyle(fontSize: fontSize * 0.9, fontWeight: FontWeight.bold)),
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
    // 💡 將原本會爆版的 Row + Expanded 改成 Wrap，小螢幕自動換行！
    return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: fontSize * 0.6,
        runSpacing: fontSize * 0.4,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: fontSize * 0.8, vertical: fontSize * 0.4),
            decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(16)),
            child: Text(label, style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
          Text(value, style: TextStyle(fontSize: fontSize * 0.9, color: Colors.black87), textAlign: TextAlign.center),
        ]
    );
  }

  // ==========================================
  // 🌟 今天聊天的回憶卡片 (動態縮放 + 圖片比例化)
  // ==========================================
  Widget _buildChatMemoriesView() {
    double fontSize = _getResponsiveFontSize(context);
    double screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              margin: EdgeInsets.all(fontSize),
              padding: EdgeInsets.all(fontSize * 1.5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: fontSize * 1.5, vertical: fontSize * 0.5),
                    decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(16)),
                    child: Text("今天聊天的回憶", style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  SizedBox(height: fontSize * 1.5),

                  // 💡 將 Row 改成 Wrap，如果平板轉直向，文字跟圖片會自動上下堆疊，不會擠爆
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: fontSize * 1.5,
                    runSpacing: fontSize * 1.5,
                    children: [
                      // 左側：文字資訊
                      SizedBox(
                        width: screenWidth > 700 ? 350 : screenWidth * 0.8,
                        child: Column(
                          children: [
                            _buildSummaryRow("主題：", _controller.originalKeywords.isNotEmpty ? _controller.originalKeywords.first : "懷舊時光", fontSize),
                            SizedBox(height: fontSize * 0.8),
                            _buildSummaryRow("內容：", _controller.originalKeywords.join("、"), fontSize),
                            SizedBox(height: fontSize * 0.8),
                            _buildSummaryRow("分享者：", _controller.elderNames.isNotEmpty ? _controller.elderNames.join("、") : "未留名", fontSize),
                          ],
                        ),
                      ),
                      // 右側：AI 生成的圖片 (動態比例)
                      Container(
                        width: screenWidth > 700 ? 300 : screenWidth * 0.8,
                        height: (screenWidth > 700 ? 300 : screenWidth * 0.8) * 0.75, // 4:3 比例
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.grey[200],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _controller.currentImageUrl.isNotEmpty
                            ? (_controller.currentImageUrl.startsWith('http') || _controller.currentImageUrl.startsWith('https')
                            ? Image.network(_controller.currentImageUrl, fit: BoxFit.cover)
                            : (kIsWeb ? Center(child: Text('Web 無法預覽', style: TextStyle(color: Colors.grey, fontSize: fontSize*0.6))) : Image.file(File(_controller.currentImageUrl), fit: BoxFit.cover)))
                            : Center(child: Icon(Icons.image, size: fontSize * 2, color: Colors.grey)),
                      ),
                    ],
                  ),
                  SizedBox(height: fontSize * 2),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD54F),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fontSize)),
                      padding: EdgeInsets.symmetric(horizontal: fontSize * 2.5, vertical: fontSize * 0.6),
                      elevation: 0,
                    ),
                    child: Text("結束", style: TextStyle(fontSize: fontSize * 0.9, fontWeight: FontWeight.bold)),
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
  // 👥 自我介紹系列視圖 (動態縮放 + Wrap)
  // ==========================================
  Widget _buildIntroView() {
    double fontSize = _getResponsiveFontSize(context);

    if (_controller.chatStatus == ChatStatus.introTransition) {
      return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: BackButton(color: Colors.black, onPressed: () => Navigator.maybePop(context))), body: Center(child: Text("我們開始聊天！", style: TextStyle(fontSize: fontSize * 1.2, fontWeight: FontWeight.bold, color: Colors.black87))));
    }
    if (_controller.chatStatus == ChatStatus.introProcessing) {
      return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: BackButton(color: Colors.black, onPressed: () => Navigator.maybePop(context))), body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.orange), SizedBox(height: fontSize), Text("正在聆聽長輩的名字...", style: TextStyle(fontSize: fontSize * 0.8, color: Colors.grey, fontWeight: FontWeight.w500))])));
    }
    return Scaffold(
      backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: BackButton(color: Colors.black, onPressed: () => Navigator.maybePop(context))),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("請大家介紹自己", style: TextStyle(fontSize: fontSize * 1.2, fontWeight: FontWeight.bold)),
              SizedBox(height: fontSize * 1.5),
              Text(_controller.currentElderName.isEmpty ? "我叫________" : "我叫 ${_controller.currentElderName}", style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500)),
              SizedBox(height: fontSize * 2.5),

              if (_controller.chatStatus == ChatStatus.introPrepare)
                _buildCircleButton("開始介紹", () => _controller.startIntroRecording(), fontSize)
              else if (_controller.chatStatus == ChatStatus.introRecording)
                Column(children: [
                  Text("🗣️ 聆聽中... (說完停頓即可)", style: TextStyle(color: Colors.grey, fontSize: fontSize * 0.7)),
                  SizedBox(height: fontSize * 0.8),
                  _buildCircleButton("停止", () => _controller.stopIntroRecordingManually(), fontSize, color: Colors.redAccent)
                ])
              else if (_controller.chatStatus == ChatStatus.introNameExtracted)
                // 💡 使用 Wrap 來放置按鈕，窄螢幕時按鈕會上下排列
                  Wrap(
                      alignment: WrapAlignment.center,
                      spacing: fontSize * 1.5,
                      runSpacing: fontSize * 1.5,
                      children: [
                        _buildCircleButton("下一位", () => _controller.nextPersonIntro(), fontSize),
                        _buildCircleButton("結束介紹", () => _controller.finishIntro(), fontSize)
                      ]
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton(String text, VoidCallback onPressed, double fontSize, {Color color = const Color(0xFFFFD54F)}) {
    return InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(fontSize * 3),
        child: Container(
          // 動態放大圓形按鈕
            width: fontSize * 4.5,
            height: fontSize * 4.5,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(text, style: TextStyle(fontSize: fontSize * 0.8, fontWeight: FontWeight.bold, color: Colors.black87))
        )
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: _getResponsiveFontSize(context) * 0.6),
            Text('等待 AI 總結並產生新問題中...', style: TextStyle(fontSize: _getResponsiveFontSize(context) * 0.7, color: Colors.grey)),
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