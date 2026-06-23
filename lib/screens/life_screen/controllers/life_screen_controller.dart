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

  // 💡 新增：儲存除錯日誌的清單
  final List<String> debugLogs = [];

  // 💡 新增：安全寫入日誌的方法 (最新的在最上面，保留近 50 筆)
  void addDebugLog(String message) {
    final timeStr = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
    debugLogs.insert(0, "[$timeStr] $message");
    if (debugLogs.length > 50) debugLogs.removeLast();
    _safeNotifyListeners();
  }

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
    addDebugLog("🚀 系統初始化完成，準備就緒");
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
    addDebugLog("🔔 [喚醒詞監聽] 收到指令: $text");
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
    addDebugLog("🎙️ [錄音] 開始自我介紹錄音...");
    // 💡 關鍵修復：給予硬體 600 毫秒切換時間，防止麥克風被鎖死錄成「靜音空軌」
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 600));
    chatStatus = ChatStatus.introRecording;
    _safeNotifyListeners();
    voiceManager.startChatFlow();
  }

  void stopIntroRecordingManually() async {
    addDebugLog("⏹️ [錄音] 手動停止自我介紹");
    await voiceManager.forceEndChat();
  }

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

    addDebugLog("🗣️ [STT 自我介紹] 辨識內容: $chunkText");

    if (chunkText.isNotEmpty) {
      try {
        currentElderName = await llmService.extractElderName(chunkText);
        addDebugLog("🧠 [LLM 名字擷取] 擷取到: $currentElderName");
      } catch (e) {
        currentElderName = "長輩";
        addDebugLog("❌ [LLM 名字擷取] 擷取失敗，使用預設值");
      }
    } else {
      currentElderName = "無名氏";
    }

    chatStatus = ChatStatus.introNameExtracted;
    voiceManager.startBackgroundWakeWordCycle();
    _safeNotifyListeners();
  }

  void nextPersonIntro() {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName);
    addDebugLog("⏭️ [流程] 記錄名字: $currentElderName，切換下一位");
    currentElderName = "";
    chatStatus = ChatStatus.introPrepare;
    voiceManager.startBackgroundWakeWordCycle();
    _safeNotifyListeners();
  }

  Future<void> finishIntro() async {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName);
    addDebugLog("✅ [流程] 結束自我介紹。參與名單: ${elderNames.join('、')}");
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
      addDebugLog("👥 [點名機制] 洗牌完成，下一位準備點名: $currentPromptElder");
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
      if (recordSeconds >= int.parse(ReminiCareConfig.maxRecordLimit)) {
        addDebugLog("⏰ [錄音超時] 達到 ${ReminiCareConfig.maxRecordLimit} 秒上限，自動結束");
        handleEndChat();
      }
    });
  }

  void stopTimer() { recordTimer?.cancel(); recordTimer = null; }

  Future<void> stopAudioSequence() async { await voiceManager.stopCurrentPlayback(); }

  void triggerStartChatFlow() async {
    if (_isIntroStatus()) return;
    stopAudioSequence();
    addDebugLog("🎙️ [錄音] 觸發對話錄音開始...");

    // 💡 關鍵修復：防止快速點擊/切換導致錄音撞車
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
    addDebugLog("⏹️ [錄音] 觸發結束錄音流程");
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

    addDebugLog("🗣️ [STT VAD自動斷句] 辨識出: $chunkText");

    accumulatedChatText += chunkText;

    if (isProcessingEnd) {
      _checkAndTriggerEndProcess();
      return;
    }

    bool isEnd = false; String cleanText = chunkText.replaceAll(" ", "");
    for (String cmd in ReminiCareConfig.endWakeWords) { if (cleanText.contains(cmd)) { isEnd = true; break; } }

    if (isEnd) {
      addDebugLog("🏁 [STT 觸發結束口令] 內容包含結束指令");
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

    if(chunkText.isNotEmpty) {
      addDebugLog("🏁 [STT 最終結算] 辨識出: $chunkText");
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

      addDebugLog("🚀 [進入 LLM 處理] 最終送出對話: $cleanTextForLLM");
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
        addDebugLog("⏭️ [點名下一位] 輪到: $currentPromptElder");
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

    addDebugLog("🤖 [LLM 初始話題] 問題: $currentMainQuestion $currentSubQuestion");

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

      addDebugLog("🤖 [LLM 請求] 產生延伸話題...");
      final String rawQuestion = await llmService.generateExtendedQuestion(previousQuestion, lastUserMessage);
      addDebugLog("🧠 [LLM 延伸話題結果] $rawQuestion");

      currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder， $rawQuestion" : rawQuestion;
      currentSubQuestion = "";

    } catch (e) {
      addDebugLog("❌ [LLM 錯誤] 延伸話題失敗: $e");
      currentMainQuestion = currentPromptElder.isNotEmpty ? "$currentPromptElder，這張照片有讓您想起更多小時候的趣味往事嗎？" : "這張照片有讓您想起更多小時候的趣味往事嗎？";
      currentSubQuestion = "";
    }
    finally { if (!_isDisposed) { isLoading = false; _safeNotifyListeners(); playCurrentContextVoice(); } }
  }

  Future<void> _generateNextTopicAndSummary({required String manualText}) async {
    try {
      addDebugLog("🤖 [LLM 請求] 總結與新一輪話題...");
      String previousQuestion = fullQuestionText;
      String extendedQuestion = await llmService.generateExtendedQuestion(previousQuestion, manualText);

      addDebugLog("🧠 [LLM 新一輪話題結果] $extendedQuestion");

      chatHistory.add({"role": "user", "content": manualText});
      chatHistory.add({"role": "assistant", "content": extendedQuestion});

      currentMainQuestion = extendedQuestion;
      currentSubQuestion = "";
    } catch (e) {
      addDebugLog("❌ [LLM 錯誤] 新一輪話題失敗: $e");
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
    addDebugLog("🔄 [流程] 總結完畢，重啟新一輪聊天");
    _resetUnspokenElders();
    chatStatus = ChatStatus.prepare;
    accumulatedChatText = "";
    fetchInitialQuestion();
    voiceManager.checkCompletedCommands = false;
    voiceManager.startBackgroundWakeWordCycle();
  }

  void finishTodayChat() {
    addDebugLog("✅ [流程] 長輩選擇結束今天聊天，進入結算畫面");
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

      addDebugLog("💾 [系統] 今日回憶卡片已成功儲存");

      if (!_isDisposed) {
        chatStatus = ChatStatus.chatMemories;
        _safeNotifyListeners();
      }
    } catch (e) {
      addDebugLog("❌ [系統錯誤] 儲存回憶失敗: $e");
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

    addDebugLog("🔊 [TTS 準備播放] ${textsToPlay.join(', ')}");

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
        addDebugLog("🤖 [LLM 請求] 正在萃取場景資訊與關鍵字...");
        final Map<String, dynamic> sceneData = await llmService.extractSceneData(promptContext);
        originalKeywords = List<String>.from(sceneData['keywords'] ?? []);
        dynamicScene = sceneData['scene']?.toString() ?? "台灣早期懷舊生活場景";
        dynamicEra = sceneData['era']?.toString() ?? "1980s";
        dynamicLocation = sceneData['location']?.toString() ?? "Taiwan";

        addDebugLog("🧠 [LLM 場景解析] 關鍵字: ${originalKeywords.join(',')} | 場景: $dynamicScene | 時代: $dynamicEra");

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
      addDebugLog("❌ [LLM 錯誤] 流程解析失敗: $e");
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
      addDebugLog("🎨 [生圖請求] 準備生成圖片... (Prompt: $prompt)");

      final String? imageUrl = await imageService.generateNostalgicImage(scene: "$dynamicScene, 包含關鍵元素: $prompt", era: dynamicEra, location: dynamicLocation);
      if (_isDisposed) return;
      if (imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.evaluation;
        addDebugLog("🖼️ [生圖成功] URL/Path: $imageUrl");
        _safeNotifyListeners();
        playCurrentContextVoice();
      }
      else throw Exception("生圖出錯");
    } catch (e) {
      addDebugLog("❌ [生圖失敗] $e");
      if (_isDisposed) return; chatStatus = ChatStatus.prepare; _safeNotifyListeners();
    }
  }

  Future<void> triggerModifiedImageGeneration(String userFeedback) async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String editInstruction = "在 $dynamicScene 的大場景氛圍下, 根據長輩的反饋修改細節：$userFeedback";
      addDebugLog("🎨 [改圖請求] $editInstruction");

      final String? imageUrl = await imageService.editImage(imagePath: currentImageUrl, editInstruction: editInstruction);
      if (_isDisposed) return;
      if (imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.evaluation;
        addDebugLog("🖼️ [改圖成功] URL/Path: $imageUrl");
        _safeNotifyListeners();
        playCurrentContextVoice();
      }
      else throw Exception("改圖出錯");
    } catch (e) {
      addDebugLog("❌ [改圖失敗] $e");
      if (_isDisposed) return; chatStatus = ChatStatus.dislikePrepare; _safeNotifyListeners();
    }
  }

  Future<void> triggerLikeExtendedImageGeneration() async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String combinedPrompt = [...originalKeywords, ...newKeywords].join("、");
      addDebugLog("🎨 [延伸話題生圖請求] Prompt: $combinedPrompt");

      final String? imageUrl = await imageService.generateNostalgicImage(scene: "$dynamicScene, 包含關鍵元素: $combinedPrompt", era: dynamicEra, location: dynamicLocation);
      if (_isDisposed) return;
      if (imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.evaluation;
        addDebugLog("🖼️ [生圖成功] URL/Path: $imageUrl");
        _safeNotifyListeners();
        playCurrentContextVoice();
      }
      else throw Exception("延伸話題生圖出錯");
    } catch (e) {
      addDebugLog("❌ [生圖失敗] $e");
      if (_isDisposed) return; chatStatus = ChatStatus.likePrepare; _safeNotifyListeners();
    }
  }

  @override
  void dispose() { _isDisposed = true; voiceManager.dispose(); stopTimer(); super.dispose(); }
}