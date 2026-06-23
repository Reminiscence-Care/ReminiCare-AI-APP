import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:remini_care_ai_app/screens/question_generator.dart';
import 'package:remini_care_ai_app/services/api_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remini_care_ai_app/services/audio_services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

enum ChatStatus {
  introPrepare, introRecording, introProcessing, introNameExtracted, introTransition,
  prepare, chatting, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeGenerating,
  nextElderPrompt, generatingNextTopic, roundSummary, chatSummary, chatMemories
}

class LifeScreenController extends ChangeNotifier {
  final ILLMService llmService = ApiServices().llm;
  final ISTTService sttService = ApiServices().stt;

  final IImageGenService imageService = ApiServices().image;

  final VoiceAssistantManager voiceManager = VoiceAssistantManager();

  ChatStatus chatStatus = ChatStatus.introPrepare;
  bool _isDisposed = false;

  bool _hasPlayedIntroGreeting = false;

  List<String> elderNames = [];
  String currentElderName = "";
  List<String> unspokenElders = [];
  String currentPromptElder = "";
  ChatStatus currentChatPhase = ChatStatus.chatting;

  String currentMainQuestion = "";
  String currentSubQuestion = "";

  String get fullQuestionText => "$currentMainQuestion $currentSubQuestion".trim();

  String selectedLanguage = "台語";
  bool isLoading = false;
  bool isExtractingKeywords = false;

  int recordSeconds = 0;
  Timer? recordTimer;

  String accumulatedChatText = "";
  bool isProcessingEnd = false;

  int _activeSttTasks = 0;
  bool _hasTriggeredEndProcess = false;

  List<String> originalKeywords = [];
  List<String> newKeywords = [];
  final List<Map<String, String>> chatHistory = [];

  String currentImageUrl = "";
  String dynamicScene = "台灣早期懷舊生活場景";
  String dynamicEra = "1980s";
  String dynamicLocation = "Taiwan";

  // 💡 安全的狀態更新：防止畫面被銷毀後仍嘗試更新 UI 導致崩潰
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  bool isVoiceActiveStatus(ChatStatus status) {
    return status == ChatStatus.prepare || status == ChatStatus.chatting ||
        status == ChatStatus.dislikePrepare || status == ChatStatus.dislikeChatting ||
        status == ChatStatus.likePrepare || status == ChatStatus.likeChatting ||
        status == ChatStatus.nextElderPrompt || status == ChatStatus.roundSummary;
  }

  Future<void> init() async {
    await ReminiCareConfig.loadConfig();

    voiceManager.onStartChatFlow = triggerStartChatFlow;
    voiceManager.onRestartChatFlow = triggerStartChatFlow;
    voiceManager.onEndChatFlow = () async {
      if (_isIntroStatus()) return;
      await stopAudioSequence();
      await voiceManager.stopActiveAudioOperations();
    };

    voiceManager.onSpeechCompleted = (mergedWavPaths) {
      if (chatStatus == ChatStatus.introRecording) {
        _handleIntroSpeechCompleted(mergedWavPaths ?? []);
      } else {
        if (isProcessingEnd) {
          handleFinalChunk(mergedWavPaths ?? []);
        } else {
          _handleVadChunk(mergedWavPaths ?? []);
        }
      }
    };

    voiceManager.onBackgroundTextRecognized = _handleBackgroundCommands;

    voiceManager.onPlayingLanguageChanged = (lang) {
      selectedLanguage = lang;
      _safeNotifyListeners();
    };

    if (chatStatus == ChatStatus.introPrepare && !_hasPlayedIntroGreeting) {
      _playIntroGreeting();
    } else {
      voiceManager.startBackgroundWakeWordCycle();
    }

    _safeNotifyListeners();
  }

  Future<void> _playIntroGreeting() async {
    _hasPlayedIntroGreeting = true;
    await stopAudioSequence();
    await voiceManager.stopActiveAudioOperations();

    await voiceManager.playLanguageSequence(
      texts: ["請大家介紹自己"],
      languages: ["台語", "中文"],
      repeatCount: 1,
    );

    if (!_isDisposed && chatStatus == ChatStatus.introPrepare) {
      voiceManager.startBackgroundWakeWordCycle();
    }
  }

  bool _isIntroStatus() =>
      chatStatus == ChatStatus.introPrepare || chatStatus == ChatStatus.introRecording ||
          chatStatus == ChatStatus.introProcessing || chatStatus == ChatStatus.introNameExtracted ||
          chatStatus == ChatStatus.introTransition;

  void _handleBackgroundCommands(String text) {
    if (_isIntroStatus()) {
      if (chatStatus == ChatStatus.introPrepare && text.contains("開始介紹")) startIntroRecording();
      else if (chatStatus == ChatStatus.introNameExtracted) {
        if (text.contains("下一位")) nextPersonIntro();
        else if (text.contains("結束介紹")) finishIntro();
      }
    } else if (chatStatus == ChatStatus.roundSummary) {
      if (text.contains("繼續")) continueChatFromSummary();
      else if (text.contains("完成") || text.contains("結束")) finishTodayChat();
    }
  }

  void startIntroRecording() async {
    await stopAudioSequence();
    // 💡 關鍵修復：如果是在播放音訊中途打斷並開始錄音，必須給予硬體 600 毫秒切換時間
    // 否則麥克風會被鎖死錄製成「靜音空軌」，導致 STT 辨識回傳 (空)
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 600));
    chatStatus = ChatStatus.introRecording;
    _safeNotifyListeners();
    voiceManager.startChatFlow();
  }

  void stopIntroRecordingManually() async => await voiceManager.forceEndChat();

  Future<void> _handleIntroSpeechCompleted(List<String> paths) async {
    if (paths.isEmpty) {
      chatStatus = ChatStatus.introPrepare;
      _safeNotifyListeners();
      return;
    }
    chatStatus = ChatStatus.introProcessing;
    _safeNotifyListeners();

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (_) {}
      if (t != null && t.trim().isNotEmpty) chunkText += t;
    }

    if (chunkText.isNotEmpty) {
      try {
        currentElderName = await llmService.extractElderName(chunkText);
      } catch (e) { currentElderName = "長輩"; }
    } else {
      currentElderName = "無名氏";
    }

    chatStatus = ChatStatus.introNameExtracted;
    voiceManager.startBackgroundWakeWordCycle();
    _safeNotifyListeners();
  }

  void nextPersonIntro() {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName);
    currentElderName = "";
    chatStatus = ChatStatus.introPrepare;
    voiceManager.startBackgroundWakeWordCycle();
    _safeNotifyListeners();
  }

  Future<void> finishIntro() async {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName);
    await voiceManager.stopActiveAudioOperations();
    chatStatus = ChatStatus.introTransition;
    _safeNotifyListeners();

    _hasPlayedIntroGreeting = false;

    await Future.delayed(const Duration(seconds: 3));

    _resetUnspokenElders();
    chatStatus = ChatStatus.prepare;
    await fetchInitialQuestion();

    voiceManager.checkCompletedCommands = false;
    voiceManager.startBackgroundWakeWordCycle();
    _safeNotifyListeners();
  }

  void _resetUnspokenElders() {
    if (elderNames.isNotEmpty) {
      unspokenElders = List.from(elderNames)..shuffle();
      currentPromptElder = unspokenElders.removeAt(0);
    } else {
      currentPromptElder = "";
    }
  }

  void startTimer() {
    recordTimer?.cancel();
    recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) { timer.cancel(); return; }
      recordSeconds++;
      _safeNotifyListeners();
      if (recordSeconds >= int.parse(ReminiCareConfig.maxRecordLimit)) handleEndChat();
    });
  }

  void stopTimer() { recordTimer?.cancel(); recordTimer = null; }

  Future<void> stopAudioSequence() async { await voiceManager.stopCurrentPlayback(); }

  void triggerStartChatFlow() async {
    if (_isIntroStatus()) return;
    stopAudioSequence();
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 600));

    bool isResumingNextElder = false;

    if (chatStatus == ChatStatus.prepare) {
      chatStatus = ChatStatus.chatting;
    } else if (chatStatus == ChatStatus.dislikePrepare) {
      chatStatus = ChatStatus.dislikeChatting;
      currentChatPhase = ChatStatus.dislikeChatting;
    } else if (chatStatus == ChatStatus.likePrepare) {
      chatStatus = ChatStatus.likeChatting;
      currentChatPhase = ChatStatus.likePrepare;
    } else if (chatStatus == ChatStatus.nextElderPrompt) {
      isResumingNextElder = true;
      int commaIndex = currentMainQuestion.indexOf("，");
      currentMainQuestion = currentMainQuestion.substring(commaIndex + 2);
      currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder， $currentMainQuestion" : currentMainQuestion;
      chatStatus = currentChatPhase;
      playCurrentContextVoice();
    } else {
      chatStatus = ChatStatus.chatting;
    }

    recordSeconds = 0;
    if (!isResumingNextElder) accumulatedChatText = "";

    isProcessingEnd = false;
    _hasTriggeredEndProcess = false;
    _activeSttTasks = 0;

    startTimer();
    _safeNotifyListeners();
    voiceManager.startChatFlow();
  }

  Future<void> handleEndChat() async {
    isProcessingEnd = true; stopTimer();
    if (_isDisposed) return;
    await voiceManager.forceEndChat();
  }

  Future<void> _handleVadChunk(List<String> paths) async {
    bool isChatting = chatStatus == ChatStatus.chatting || chatStatus == ChatStatus.dislikeChatting || chatStatus == ChatStatus.likeChatting;
    if (!isProcessingEnd && isChatting) voiceManager.startChatFlow();
    if (paths.isEmpty) return;

    _activeSttTasks++;

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (_) {}
      if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
    }

    _activeSttTasks--;

    if (chunkText.isEmpty) {
      if (isProcessingEnd) _checkAndTriggerEndProcess();
      return;
    }

    accumulatedChatText += chunkText;

    if (isProcessingEnd) {
      _checkAndTriggerEndProcess();
      return;
    }

    bool isEnd = false; String cleanText = chunkText.replaceAll(" ", "");
    for (String cmd in ReminiCareConfig.endWakeWords) { if (cleanText.contains(cmd)) { isEnd = true; break; } }

    if (isEnd) {
      isProcessingEnd = true; stopTimer(); await voiceManager.stopActiveAudioOperations();
      _checkAndTriggerEndProcess();
    }
  }

  Future<void> handleFinalChunk(List<String> paths) async {
    _activeSttTasks++;

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (e) {}
      if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
    }
    accumulatedChatText += chunkText;

    _activeSttTasks--;

    _checkAndTriggerEndProcess();
  }

  void _checkAndTriggerEndProcess() {
    if (isProcessingEnd && _activeSttTasks == 0 && !_hasTriggeredEndProcess) {
      _hasTriggeredEndProcess = true;
      String cleanTextForLLM = accumulatedChatText;
      for (String cmd in ReminiCareConfig.endWakeWords) {
        cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
      }
      _processEndOfSpeechChunk(cleanTextForLLM);
    }
  }

  Future<void> _processEndOfSpeechChunk(String cleanTextForLLM) async {
    if (chatStatus == ChatStatus.chatting) {
      chatStatus = ChatStatus.generating;
      _safeNotifyListeners();
      _processAudioAndExtractKeywords(manualText: cleanTextForLLM);
    }
    else if (chatStatus == ChatStatus.dislikeChatting) {
      chatStatus = ChatStatus.dislikeGenerating;
      _safeNotifyListeners();
      _processAudioAndExtractKeywords(manualText: cleanTextForLLM);
    }
    else if (chatStatus == ChatStatus.likeChatting) {
      if (unspokenElders.isNotEmpty) {
        currentPromptElder = unspokenElders.removeAt(0);
        chatStatus = ChatStatus.nextElderPrompt;
        _safeNotifyListeners();
        playCurrentContextVoice();
      } else {
        chatStatus = ChatStatus.generatingNextTopic;
        _safeNotifyListeners();
        _generateNextTopicAndSummary(manualText: cleanTextForLLM);
      }
    }
  }

  Future<void> fetchInitialQuestion() async {
    if (_isDisposed) return; isLoading = true; _safeNotifyListeners();

    final List<String> q = TopicQuestionGenerator.generateLifeQuestion();
    final String rawMain = q[0];
    final String rawSub = q[1];

    currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder， $rawMain" : rawMain;
    currentSubQuestion = rawSub;

    if (!_isDisposed) {
      isLoading = false;
      _safeNotifyListeners();
      playCurrentContextVoice();
    }
  }

  Future<void> handleLikeAndGenerateExtension() async {
    if (_isDisposed) return; isLoading = true; chatStatus = ChatStatus.likePrepare; _safeNotifyListeners();
    try {
      String previousQuestion = fullQuestionText;
      String lastUserMessage = "";
      for (var msg in chatHistory.reversed) { if (msg['role'] == 'user') { lastUserMessage = msg['content'] ?? ""; break; } }
      if (lastUserMessage.isEmpty) lastUserMessage = accumulatedChatText;
      final String rawQuestion = await llmService.generateExtendedQuestion(previousQuestion, lastUserMessage);

      currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder， $rawQuestion" : rawQuestion;
      currentSubQuestion = "";

    } catch (e) {
      currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder，這張照片有讓您想起更多小時候的趣味往事嗎？" : "這張照片有讓您想起更多小時候的趣味往事嗎？";
      currentSubQuestion = "";
    }
    finally { if (!_isDisposed) { isLoading = false; _safeNotifyListeners(); playCurrentContextVoice(); } }
  }

  Future<void> _generateNextTopicAndSummary({required String manualText}) async {
    try {
      String previousQuestion = fullQuestionText;
      String extendedQuestion = await llmService.generateExtendedQuestion(previousQuestion, manualText);
      chatHistory.add({"role": "user", "content": manualText});
      chatHistory.add({"role": "assistant", "content": extendedQuestion});

      currentMainQuestion = extendedQuestion;
      currentSubQuestion = "";
    } catch (e) {
      currentMainQuestion = "剛剛聊得很棒！大家還有想到什麼有趣的事嗎？";
      currentSubQuestion = "";
    }
    finally {
      if (!_isDisposed) {
        chatStatus = ChatStatus.roundSummary; _safeNotifyListeners();
        playCurrentContextVoice();
        voiceManager.checkCompletedCommands = false; voiceManager.startBackgroundWakeWordCycle();
      }
    }
  }

  void continueChatFromSummary() {
    _resetUnspokenElders();
    chatStatus = ChatStatus.prepare;
    accumulatedChatText = "";
    fetchInitialQuestion();
    voiceManager.checkCompletedCommands = false;
    voiceManager.startBackgroundWakeWordCycle();
  }

  void finishTodayChat() {
    chatStatus = ChatStatus.chatSummary;
    _safeNotifyListeners();
    voiceManager.stopActiveAudioOperations();
  }

  Future<void> saveAndShowMemories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final String today = "${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}";

      final Map<String, dynamic> memoryData = {
        "date": today,
        "topic": originalKeywords.isNotEmpty ? originalKeywords.first : "懷舊時光",
        "content": originalKeywords.join("、"),
        "elders": elderNames.isNotEmpty ? elderNames.join("、") : "未留名",
        "imagePath": currentImageUrl,
      };

      List<String> history = prefs.getStringList('chat_memories') ?? [];
      history.add(jsonEncode(memoryData));
      await prefs.setStringList('chat_memories', history);

      if (!_isDisposed) {
        chatStatus = ChatStatus.chatMemories;
        _safeNotifyListeners();
      }
    } catch (e) {
      debugPrint("❌ 儲存回憶失敗: $e");
    }
  }

  Future<void> playCurrentContextVoice({
    bool isManualTap = false,
  }) async {
    if (_isDisposed) return;

    List<String> textsToPlay = [];

    int partGapMs = 150;

    if (chatStatus == ChatStatus.evaluation ||
        chatStatus == ChatStatus.dislikeEvaluation) {
      textsToPlay = ["這張圖符合您的回憶嗎？"];
    } else if (chatStatus == ChatStatus.dislikePrepare) {
      textsToPlay = ["哪裡不對？"];
    } else if (chatStatus == ChatStatus.nextElderPrompt) {
      textsToPlay = ["$currentPromptElder呢？"];
    } else if (chatStatus == ChatStatus.roundSummary) {
      textsToPlay = [currentMainQuestion];
    } else {
      if (currentPromptElder.isNotEmpty) {
        textsToPlay.add(currentPromptElder);
      }

      String rawMain = currentMainQuestion;
      if (currentPromptElder.isNotEmpty && rawMain.startsWith(currentPromptElder)) {
        rawMain = rawMain.substring(currentPromptElder.length).replaceAll(RegExp(r'^[，,\s]+'), '');
      }

      String combinedQuestion = "$rawMain $currentSubQuestion".trim();
      if (combinedQuestion.isNotEmpty) {
        textsToPlay.add(combinedQuestion);
      }
    }

    if (textsToPlay.isEmpty) return;

    await stopAudioSequence();
    await voiceManager.stopActiveAudioOperations();

    await Future.delayed(const Duration(milliseconds: 500));

    if (isManualTap) {
      await voiceManager.playLanguageSequence(
          texts: textsToPlay,
          languages: [selectedLanguage],
          repeatCount: 1,
          partGapMs: partGapMs
      );
    } else {
      await voiceManager.playLanguageSequence(
          texts: textsToPlay,
          languages: ["台語", "中文"],
          repeatCount: 2,
          partGapMs: partGapMs
      );
    }

    if (!_isDisposed && isVoiceActiveStatus(chatStatus)) {
      voiceManager.startBackgroundWakeWordCycle();
    }
  }

  Future<void> _processAudioAndExtractKeywords({String? manualText}) async {
    if (_isDisposed) return;
    String userMessage = manualText ?? "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";
    try {
      String contextStr = chatHistory.map((msg) => "${msg['role'] == 'user' ? '長輩' : 'AI'}: ${msg['content']}").join("\n");
      String promptContext = contextStr.isNotEmpty ? "【之前的對話脈絡】\n$contextStr\n\n" : "";
      promptContext += "【AI最新提問】: $fullQuestionText\n【長輩最新回答】: $userMessage\n\n請根據以上完整對話脈絡，提取出具體的懷舊畫面場景與視覺關鍵字。";

      if (chatStatus == ChatStatus.dislikeGenerating) {
        chatHistory.add({"role": "user", "content": userMessage});
        await triggerModifiedImageGeneration(userMessage);
      } else {
        final Map<String, dynamic> sceneData = await llmService.extractSceneData(promptContext);
        originalKeywords = List<String>.from(sceneData['keywords'] ?? []);
        dynamicScene = sceneData['scene']?.toString() ?? "台灣早期懷舊生活場景";
        dynamicEra = sceneData['era']?.toString() ?? "1980s";
        dynamicLocation = sceneData['location']?.toString() ?? "Taiwan";

        if (_isDisposed) return;
        newKeywords = originalKeywords;
        chatHistory.add({"role": "user", "content": userMessage});

        if (chatStatus == ChatStatus.likeGenerating) {
          await triggerLikeExtendedImageGeneration();
        } else {
          await triggerImageGeneration();
        }
      }
    } catch (e) {
      if (_isDisposed) return;
      currentMainQuestion = "阿公阿嬤拍謝，我剛才不小心恍神了，可以再跟我說一次嗎？";
      currentSubQuestion = "";
      chatStatus = chatStatus == ChatStatus.dislikeGenerating ? ChatStatus.dislikePrepare : ChatStatus.prepare;
      _safeNotifyListeners();
      await voiceManager.playLanguageSequence(
        texts: [currentMainQuestion],
        languages: ["台語", "中文"],
        repeatCount: 2,
      );
    }
  }

  Future<void> triggerImageGeneration() async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String prompt = originalKeywords.join("、"); if (prompt.isEmpty) prompt = "懷舊元素";
      final String? imageUrl = await imageService.generateNostalgicImage(scene: "$dynamicScene, 包含關鍵元素: $prompt", era: dynamicEra, location: dynamicLocation);
      if (_isDisposed) return;
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; _safeNotifyListeners(); playCurrentContextVoice(); }
      else throw Exception("生圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.prepare; _safeNotifyListeners(); }
  }

  Future<void> triggerModifiedImageGeneration(String userFeedback) async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String editInstruction = "在 $dynamicScene 的大場景氛圍下, 根據長輩的反饋修改細節：$userFeedback";
      final String? imageUrl = await imageService.editImage(imagePath: currentImageUrl, editInstruction: editInstruction);
      if (_isDisposed) return;
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; _safeNotifyListeners(); playCurrentContextVoice(); }
      else throw Exception("改圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.dislikePrepare; _safeNotifyListeners(); }
  }

  Future<void> triggerLikeExtendedImageGeneration() async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String combinedPrompt = [...originalKeywords, ...newKeywords].join("、");
      final String? imageUrl = await imageService.generateNostalgicImage(scene: "$dynamicScene, 包含關鍵元素: $combinedPrompt", era: dynamicEra, location: dynamicLocation);
      if (_isDisposed) return;
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; _safeNotifyListeners(); playCurrentContextVoice(); }
      else throw Exception("延伸話題生圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.likePrepare; _safeNotifyListeners(); }
  }

  @override
  void dispose() { _isDisposed = true; voiceManager.dispose(); stopTimer(); super.dispose(); }
}