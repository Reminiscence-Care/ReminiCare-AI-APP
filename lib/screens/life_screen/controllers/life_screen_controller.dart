import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remini_care_ai_app/services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/llm_services/nvidia_llm_service.dart';
import 'package:remini_care_ai_app/services/speech_services.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:remini_care_ai_app/screens/question_generator.dart';

enum ChatStatus {
  introPrepare, introRecording, introProcessing, introNameExtracted, introTransition,
  prepare, chatting, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeGenerating,
  nextElderPrompt, generatingNextTopic, roundSummary, chatSummary, chatMemories
}

class LifeScreenController extends ChangeNotifier {
  final NvidiaLlmService llmService = NvidiaLlmService();
  final ISTTService sttService = YatingSpeechService();

  final IImageGenService imageService = SiliconFlowImageService(
    rawBaseUrl: "https://api.siliconflow.com/v1",
    apiKeyProvider: () => ReminiCareConfig.siliconFlowApiKey,
    generationModel: "Qwen/Qwen-Image",
    editModel: "Qwen/Qwen-Image-Edit",
    defaultNegativePrompt: "Simplified Chinese, deformed strokes",
  );

  final VoiceAssistantManager voiceManager = VoiceAssistantManager();

  ChatStatus chatStatus = ChatStatus.introPrepare;
  bool _isDisposed = false;

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

  // 💡 新增：用來追蹤還在排隊等 Yating STT 辨識的任務數量與觸發狀態
  int _activeSttTasks = 0;
  bool _hasTriggeredEndProcess = false;

  List<String> originalKeywords = [];
  List<String> newKeywords = [];
  final List<Map<String, String>> chatHistory = [];

  String currentImageUrl = "";
  String dynamicScene = "台灣早期懷舊生活場景";
  String dynamicEra = "1980s";
  String dynamicLocation = "Taiwan";

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
      notifyListeners();
    };

    voiceManager.startBackgroundWakeWordCycle();
    notifyListeners();
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
    } else if (chatStatus == ChatStatus.nextElderPrompt && (text.contains("開始") || text.contains("聊天") || text.contains("錄音"))) {
      triggerStartChatFlow();
    } else if (chatStatus == ChatStatus.roundSummary) {
      if (text.contains("繼續")) continueChatFromSummary();
      else if (text.contains("完成") || text.contains("結束")) finishTodayChat();
    }
  }

  void startIntroRecording() async { await stopAudioSequence(); chatStatus = ChatStatus.introRecording; notifyListeners(); voiceManager.startChatFlow(); }
  void stopIntroRecordingManually() async => await voiceManager.forceEndChat();
  Future<void> _handleIntroSpeechCompleted(List<String> paths) async {
    if (paths.isEmpty) { chatStatus = ChatStatus.introPrepare; notifyListeners(); return; }
    chatStatus = ChatStatus.introProcessing; notifyListeners();
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

    chatStatus = ChatStatus.introNameExtracted; voiceManager.startBackgroundWakeWordCycle(); notifyListeners();
  }
  void nextPersonIntro() {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName);
    currentElderName = ""; chatStatus = ChatStatus.introPrepare; voiceManager.startBackgroundWakeWordCycle(); notifyListeners();
  }

  Future<void> finishIntro() async {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName);
    await voiceManager.stopActiveAudioOperations();
    chatStatus = ChatStatus.introTransition; notifyListeners();
    await Future.delayed(const Duration(seconds: 3));

    _resetUnspokenElders();
    chatStatus = ChatStatus.prepare;
    await fetchInitialQuestion();

    voiceManager.checkCompletedCommands = false;
    voiceManager.startBackgroundWakeWordCycle(); notifyListeners();
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
      notifyListeners();
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
      currentChatPhase = ChatStatus.likeChatting;
    } else if (chatStatus == ChatStatus.nextElderPrompt) {
      isResumingNextElder = true;
      chatStatus = currentChatPhase;
    } else {
      chatStatus = ChatStatus.chatting;
    }

    recordSeconds = 0;
    if (!isResumingNextElder) accumulatedChatText = "";

    isProcessingEnd = false;
    _hasTriggeredEndProcess = false;
    _activeSttTasks = 0;

    startTimer();
    notifyListeners();
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

    // 💡 標記：有一個 STT 任務正在進行中
    _activeSttTasks++;

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (_) {}
      if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
    }

    // 💡 標記：這個 STT 任務完成了
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
    // 💡 標記：最後一段強制結算的 STT 任務正在進行中
    _activeSttTasks++;

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (e) {}
      if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
    }
    accumulatedChatText += chunkText;

    // 💡 標記：任務完成
    _activeSttTasks--;

    _checkAndTriggerEndProcess();
  }

  void _checkAndTriggerEndProcess() {
    // 必須符合：1. 已經標記結束 2. 所有翻譯都回來了 3. 還沒觸發過 AI
    if (isProcessingEnd && _activeSttTasks == 0 && !_hasTriggeredEndProcess) {
      _hasTriggeredEndProcess = true; // 鎖上，避免重複觸發
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
      notifyListeners();
      _processAudioAndExtractKeywords(manualText: cleanTextForLLM);
    }
    else if (chatStatus == ChatStatus.dislikeChatting) {
      chatStatus = ChatStatus.dislikeGenerating; notifyListeners();
      _processAudioAndExtractKeywords(manualText: cleanTextForLLM);
    }
    else if (chatStatus == ChatStatus.likeChatting) {
      if (unspokenElders.isNotEmpty) {
        currentPromptElder = unspokenElders.removeAt(0);
        chatStatus = ChatStatus.nextElderPrompt; notifyListeners();
        playCurrentContextVoice();
      } else {
        chatStatus = ChatStatus.generatingNextTopic; notifyListeners();
        _generateNextTopicAndSummary(manualText: cleanTextForLLM);
      }
    }
  }

  Future<void> fetchInitialQuestion() async {
    if (_isDisposed) return; isLoading = true; notifyListeners();

    final List<String> q = TopicQuestionGenerator.generateLifeQuestion();
    final String rawMain = q[0];
    final String rawSub = q[1];

    currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder， $rawMain" : rawMain;
    currentSubQuestion = rawSub;

    if (!_isDisposed) {
      isLoading = false;
      notifyListeners();
      playCurrentContextVoice();
    }
  }

  Future<void> handleLikeAndGenerateExtension() async {
    if (_isDisposed) return; isLoading = true; chatStatus = ChatStatus.likePrepare; notifyListeners();
    try {
      String previousQuestion = fullQuestionText;
      String lastUserMessage = "";
      for (var msg in chatHistory.reversed) { if (msg['role'] == 'user') { lastUserMessage = msg['content'] ?? ""; break; } }
      if (lastUserMessage.isEmpty) lastUserMessage = accumulatedChatText;
      final String rawQuestion = await llmService.generateExtendedQuestion(previousQuestion, lastUserMessage);

      if(unspokenElders.isNotEmpty) {
        currentPromptElder = unspokenElders.removeAt(0);
        currentMainQuestion = "$currentPromptElder， $rawQuestion";
      } else {
        currentMainQuestion = rawQuestion;
      }
      currentSubQuestion = "";

    } catch (e) {
      currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder，這張照片有讓您想起更多小時候的趣味往事嗎？" : "這張照片有讓您想起更多小時候的趣味往事嗎？";
      currentSubQuestion = "";
    }
    finally { if (!_isDisposed) { isLoading = false; notifyListeners(); playCurrentContextVoice(); } }
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
        chatStatus = ChatStatus.roundSummary; notifyListeners();
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
    notifyListeners();
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
        notifyListeners();
      }
    } catch (e) {
      debugPrint("❌ 儲存回憶失敗: $e");
    }
  }

  // 💡 關鍵分割：把「長輩名字」與「實際問題」拆開成為字串陣列，讓快取能精準命中！
  Future<void> playCurrentContextVoice({
    bool isManualTap = false,
  }) async {
    if (_isDisposed) return;

    List<String> textsToPlay = [];

    if (chatStatus == ChatStatus.evaluation ||
        chatStatus == ChatStatus.dislikeEvaluation) {
      textsToPlay = ["這張圖符合您的回憶嗎？"];
    } else if (chatStatus == ChatStatus.dislikePrepare) {
      textsToPlay = ["哪裡不對？"];
    } else if (chatStatus == ChatStatus.nextElderPrompt) {
      textsToPlay = ["$currentPromptElder呢？"]; // 短句子可以直接合成一組
    } else {
      // 提取並拆分長輩姓名，其餘部分合併成一個純淨的題目字串
      if (currentPromptElder.isNotEmpty) {
        textsToPlay.add(currentPromptElder);
      }

      String rawMain = currentMainQuestion;
      if (currentPromptElder.isNotEmpty && rawMain.startsWith(currentPromptElder)) {
        // 移除名字與緊接在後的逗點與空白
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

    if (isManualTap) {
      await voiceManager.playLanguageSequence(
        texts: textsToPlay,
        languages: [selectedLanguage],
        repeatCount: 1,
      );
    } else {
      await voiceManager.playLanguageSequence(
        texts: textsToPlay,
        languages: ["台語", "中文"],
        repeatCount: 2,
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
      notifyListeners();
      // 💡 錯誤處理也使用陣列模式送出
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
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; notifyListeners(); playCurrentContextVoice(); }
      else throw Exception("生圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.prepare; notifyListeners(); }
  }

  Future<void> triggerModifiedImageGeneration(String userFeedback) async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String editInstruction = "在 $dynamicScene 的大場景氛圍下, 根據長輩的反饋修改細節：$userFeedback";
      final String? imageUrl = await imageService.editImage(imagePath: currentImageUrl, editInstruction: editInstruction);
      if (_isDisposed) return;
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; notifyListeners(); playCurrentContextVoice(); }
      else throw Exception("改圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.dislikePrepare; notifyListeners(); }
  }

  Future<void> triggerLikeExtendedImageGeneration() async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String combinedPrompt = [...originalKeywords, ...newKeywords].join("、");
      final String? imageUrl = await imageService.generateNostalgicImage(scene: "$dynamicScene, 包含關鍵元素: $combinedPrompt", era: dynamicEra, location: dynamicLocation);
      if (_isDisposed) return;
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; notifyListeners(); playCurrentContextVoice(); }
      else throw Exception("延伸話題生圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.likePrepare; notifyListeners(); }
  }

  @override
  void dispose() { _isDisposed = true; voiceManager.dispose(); stopTimer(); super.dispose(); }
}