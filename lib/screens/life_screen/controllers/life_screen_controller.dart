import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'package:remini_care_ai_app/services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/nvidia_llm_service.dart';
import 'package:remini_care_ai_app/services/speech_services.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

enum ChatStatus {
  // --- 自我介紹狀態 ---
  introPrepare, introRecording, introProcessing, introNameExtracted, introTransition,
  // --- 原有的對話狀態 ---
  prepare, chatting, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeGenerating,
  // --- 🌟 新增的輪流與總結狀態 ---
  nextElderPrompt,
  generatingNextTopic,
  roundSummary,
  chatSummary
}

class LifeScreenController extends ChangeNotifier {
  final NvidiaLlmService llmService = NvidiaLlmService();
  final ITTSService ttsService = YatingSpeechService();
  final ISTTService sttService = YatingSpeechService();

  final UniversalImageService imageService = UniversalImageService(
    rawBaseUrl: "https://api.siliconflow.com/v1",
    apiKeyProvider: () => ReminiCareConfig.siliconFlowApiKey,
    generationModel: "Qwen/Qwen-Image",
    editModel: "Qwen/Qwen-Image-Edit",
    defaultNegativePrompt: "Simplified Chinese, deformed strokes",
  );

  final VoiceAssistantManager voiceManager = VoiceAssistantManager();
  final AudioPlayer audioPlayer = AudioPlayer();

  ChatStatus chatStatus = ChatStatus.introPrepare;
  bool _isDisposed = false;

  // --- 長輩名單與輪流機制 ---
  List<String> elderNames = [];
  String currentElderName = "";
  List<String> unspokenElders = [];
  String currentPromptElder = "";
  ChatStatus currentChatPhase = ChatStatus.chatting;

  String aiGeneratedText = "";
  String selectedLanguage = "台語";
  bool isLoading = false;
  bool isExtractingKeywords = false;

  int recordSeconds = 0;
  Timer? recordTimer;

  String accumulatedChatText = "";
  bool isProcessingEnd = false;

  List<String> originalKeywords = [];
  List<String> newKeywords = [];
  final List<Map<String, String>> chatHistory = [];

  String currentImageUrl = "";
  String dynamicScene = "台灣早期懷舊生活場景";
  String dynamicEra = "1980s";
  String dynamicLocation = "Taiwan";

  int currentPlaySessionId = 0;

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

  // --- Intro Logic 省略 (同原版) ---
  void startIntroRecording() async { await stopAudioSequence(); chatStatus = ChatStatus.introRecording; notifyListeners(); voiceManager.startChatFlow(); }
  void stopIntroRecordingManually() async => await voiceManager.forceEndChat();
  Future<void> _handleIntroSpeechCompleted(List<String> paths) async {
    if (paths.isEmpty) { chatStatus = ChatStatus.introPrepare; notifyListeners(); return; }
    chatStatus = ChatStatus.introProcessing; notifyListeners();
    String chunkText = ""; for (String path in paths) { String? t = await sttService.transcribe(path); try { File(path).deleteSync(); } catch (_) {} if (t != null && t.trim().isNotEmpty) chunkText += t; }
    if (chunkText.isNotEmpty) { try { currentElderName = await llmService.generateChatReply("從這句擷取長輩名字或稱呼(如王阿嬤),沒有就回傳「無名氏」: $chunkText", []); } catch (e) { currentElderName = "長輩"; } } else { currentElderName = "無名氏"; }
    chatStatus = ChatStatus.introNameExtracted; voiceManager.startBackgroundWakeWordCycle(); notifyListeners();
  }
  void nextPersonIntro() { if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName); currentElderName = ""; chatStatus = ChatStatus.introPrepare; voiceManager.startBackgroundWakeWordCycle(); notifyListeners(); }
  Future<void> finishIntro() async {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") elderNames.add(currentElderName);
    await voiceManager.stopActiveAudioOperations(); chatStatus = ChatStatus.introTransition; notifyListeners();
    await Future.delayed(const Duration(seconds: 3)); chatStatus = ChatStatus.prepare; await fetchInitialQuestion();
    voiceManager.checkCompletedCommands = false; voiceManager.startBackgroundWakeWordCycle(); notifyListeners();
  }

  void startTimer() { recordTimer?.cancel(); recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) { if (_isDisposed) { timer.cancel(); return; } recordSeconds++; notifyListeners(); if (recordSeconds >= int.parse(ReminiCareConfig.maxRecordLimit)) handleEndChat(); }); }
  void stopTimer() { recordTimer?.cancel(); recordTimer = null; }
  Future<void> stopAudioSequence() async { currentPlaySessionId++; try { await audioPlayer.stop(); } catch (_) {} }

  void triggerStartChatFlow() async {
    if (_isIntroStatus()) return;
    stopAudioSequence();
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 600));

    bool isResumingNextElder = false;

    // 💡 第一輪聊天不設定輪流，只有進入 likePrepare 延伸話題才會抽籤排隊！
    if (chatStatus == ChatStatus.prepare) {
      chatStatus = ChatStatus.chatting;
    } else if (chatStatus == ChatStatus.dislikePrepare) {
      chatStatus = ChatStatus.dislikeChatting;
      currentChatPhase = ChatStatus.dislikeChatting;
      unspokenElders = List.from(elderNames)..shuffle();
      if (unspokenElders.isNotEmpty) unspokenElders.removeAt(0);
    } else if (chatStatus == ChatStatus.likePrepare) {
      chatStatus = ChatStatus.likeChatting;
      currentChatPhase = ChatStatus.likeChatting;
      unspokenElders = List.from(elderNames)..shuffle();
      if (unspokenElders.isNotEmpty) unspokenElders.removeAt(0);
    } else if (chatStatus == ChatStatus.nextElderPrompt) {
      isResumingNextElder = true;
      chatStatus = currentChatPhase; // 接續回 likeChatting
    } else {
      chatStatus = ChatStatus.chatting;
    }

    recordSeconds = 0;
    if (!isResumingNextElder) accumulatedChatText = "";
    isProcessingEnd = false; startTimer(); notifyListeners(); voiceManager.startChatFlow();
  }

  Future<void> handleEndChat() async {
    isProcessingEnd = true; stopTimer();
    if (_isDisposed) return;
    // 不要在這裡強硬設定狀態，交給 _processEndOfSpeechChunk 處理！
    await voiceManager.forceEndChat();
  }

  Future<void> _handleVadChunk(List<String> paths) async {
    bool isChatting = chatStatus == ChatStatus.chatting || chatStatus == ChatStatus.dislikeChatting || chatStatus == ChatStatus.likeChatting;
    if (!isProcessingEnd && isChatting) voiceManager.startChatFlow();
    if (paths.isEmpty) return;

    String chunkText = "";
    for (String path in paths) { String? t = await sttService.transcribe(path); try { File(path).deleteSync(); } catch (_) {} if (t != null && t.trim().isNotEmpty) chunkText += t + "，"; }
    if (chunkText.isEmpty) return;
    if (isProcessingEnd) { accumulatedChatText += chunkText; return; }

    bool isEnd = false; String cleanText = chunkText.replaceAll(" ", "");
    for (String cmd in ReminiCareConfig.endWakeWords) { if (cleanText.contains(cmd)) { isEnd = true; break; } }

    if (isEnd) {
      isProcessingEnd = true; stopTimer(); await voiceManager.stopActiveAudioOperations();
      accumulatedChatText += chunkText;
      String cleanTextForLLM = accumulatedChatText; for (String cmd in ReminiCareConfig.endWakeWords) cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
      await _processEndOfSpeechChunk(cleanTextForLLM);
    } else {
      accumulatedChatText += chunkText;
    }
  }

  Future<void> handleFinalChunk(List<String> paths) async {
    String chunkText = "";
    for (String path in paths) { String? t = await sttService.transcribe(path); try { File(path).deleteSync(); } catch (e) {} if (t != null && t.trim().isNotEmpty) chunkText += t + "，"; }
    accumulatedChatText += chunkText;
    String cleanTextForLLM = accumulatedChatText; for (String cmd in ReminiCareConfig.endWakeWords) cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
    await _processEndOfSpeechChunk(cleanTextForLLM);
  }

  // 🌟 核心：判定是換下一個長輩，還是結束這一輪！
  Future<void> _processEndOfSpeechChunk(String cleanTextForLLM) async {
    if (chatStatus == ChatStatus.chatting) {
      // 第一輪：直接生圖，不輪流
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
        _playAlternatingSequence("$currentPromptElder呢？");
      } else {
        // ✅ 大家都對這張圖講完了，總結並產生「新話題」
        chatStatus = ChatStatus.generatingNextTopic; notifyListeners();
        _generateNextTopicAndSummary(manualText: cleanTextForLLM);
      }
    }
  }

  Future<void> fetchInitialQuestion() async {
    if (_isDisposed) return; isLoading = true; notifyListeners();
    try {
      aiGeneratedText = await llmService.generateInitialQuestion();
    } catch (e) { aiGeneratedText = "哈囉！小時候家裡最常吃什麼呢？"; }
    finally { if (!_isDisposed) { isLoading = false; notifyListeners(); playCurrentContextVoice(selectedLanguage); } }
  }

  Future<void> handleLikeAndGenerateExtension() async {
    if (_isDisposed) return; isLoading = true; chatStatus = ChatStatus.likePrepare; notifyListeners();
    try {
      String previousQuestion = aiGeneratedText; String lastUserMessage = "";
      for (var msg in chatHistory.reversed) { if (msg['role'] == 'user') { lastUserMessage = msg['content'] ?? ""; break; } }
      if (lastUserMessage.isEmpty) lastUserMessage = accumulatedChatText;
      aiGeneratedText = await llmService.generateExtendedQuestion(previousQuestion, lastUserMessage);
    } catch (e) { aiGeneratedText = "這張照片有讓您想起更多小時候的趣味往事嗎？"; }
    finally { if (!_isDisposed) { isLoading = false; notifyListeners(); playCurrentContextVoice(selectedLanguage); } }
  }

  // 🌟 產生輪迴新話題
  Future<void> _generateNextTopicAndSummary({required String manualText}) async {
    try {
      String previousQuestion = aiGeneratedText;
      String extendedQuestion = await llmService.generateExtendedQuestion(previousQuestion, manualText);
      chatHistory.add({"role": "user", "content": manualText});
      chatHistory.add({"role": "assistant", "content": extendedQuestion});
      aiGeneratedText = extendedQuestion;
    } catch (e) { aiGeneratedText = "剛剛聊得很棒！大家還有想到什麼有趣的事嗎？"; }
    finally {
      if (!_isDisposed) {
        chatStatus = ChatStatus.roundSummary; notifyListeners();
        playCurrentContextVoice(selectedLanguage);
        voiceManager.checkCompletedCommands = false; voiceManager.startBackgroundWakeWordCycle();
      }
    }
  }

  // 💡 當按下「繼續聊天」，帶入剛剛產生的新話題，回到像 likePrepare 一樣的準備狀態
  void continueChatFromSummary() {
    chatStatus = ChatStatus.likePrepare;
    accumulatedChatText = "";
    notifyListeners();
    playCurrentContextVoice(selectedLanguage);
    voiceManager.checkCompletedCommands = false;
    voiceManager.startBackgroundWakeWordCycle();
  }

  void finishTodayChat() {
    chatStatus = ChatStatus.chatSummary;
    notifyListeners();
    voiceManager.stopActiveAudioOperations();
  }

  void playCurrentContextVoice(String lang) {
    if (_isDisposed) return;
    String textToPlay = aiGeneratedText;
    if (chatStatus == ChatStatus.evaluation || chatStatus == ChatStatus.dislikeEvaluation) textToPlay = "這張圖符合您的回憶嗎？";
    else if (chatStatus == ChatStatus.dislikePrepare) textToPlay = "哪裡不對？";
    else if (chatStatus == ChatStatus.nextElderPrompt) textToPlay = "$currentPromptElder呢？";
    else if (chatStatus == ChatStatus.likePrepare || chatStatus == ChatStatus.likeChatting || chatStatus == ChatStatus.roundSummary) textToPlay = aiGeneratedText;
    _playSingleVoice(textToPlay, lang);
  }

  Future<void> _playSingleVoice(String text, String language) async {
    await stopAudioSequence(); await voiceManager.stopActiveAudioOperations();
    if (text.isEmpty || kIsWeb) return;
    final sessionId = currentPlaySessionId;
    try {
      selectedLanguage = language; notifyListeners();
      final Uint8List? audioBytes = await ttsService.generateSpeech(text, language);
      if (audioBytes != null) {
        if (_isDisposed || sessionId != currentPlaySessionId) return;
        String safeLang = (language == "台語") ? "tw" : "zh";
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/tts_single_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');
        await file.writeAsBytes(audioBytes, flush: true);
        await Future.delayed(const Duration(milliseconds: 150));
        if (_isDisposed || sessionId != currentPlaySessionId) return;
        await audioPlayer.play(DeviceFileSource(file.path));
        await Future.delayed(const Duration(milliseconds: 100));
        Duration? duration = await audioPlayer.getDuration();
        int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
        int elapsed = 0;
        while (elapsed < waitMs) {
          if (_isDisposed || sessionId != currentPlaySessionId) { try { await audioPlayer.stop(); } catch (_) {} return; }
          await Future.delayed(const Duration(milliseconds: 100)); elapsed += 100;
        }
      }
    } catch (e) { debugPrint("[單次播放錯誤]: $e"); } finally {
      if (sessionId == currentPlaySessionId && !_isDisposed && isVoiceActiveStatus(chatStatus)) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_isDisposed && sessionId == currentPlaySessionId && isVoiceActiveStatus(chatStatus)) voiceManager.startBackgroundWakeWordCycle();
        });
      }
    }
  }

  Future<void> _playAlternatingSequence(String text) async {
    await stopAudioSequence(); await voiceManager.stopActiveAudioOperations();
    if (text.isEmpty || kIsWeb) return;
    final sessionId = currentPlaySessionId;
    final sequence = ["台語", "中文", "台語", "中文"];
    final Map<String, Uint8List> localTtsCacheBytes = {};

    for (final lang in sequence) {
      if (_isDisposed || sessionId != currentPlaySessionId) return;
      try {
        Uint8List? audioBytes;
        if (localTtsCacheBytes.containsKey(lang)) audioBytes = localTtsCacheBytes[lang];
        else { audioBytes = await ttsService.generateSpeech(text, lang); if (audioBytes != null) localTtsCacheBytes[lang] = audioBytes; }

        if (audioBytes != null && !_isDisposed && sessionId == currentPlaySessionId) {
          selectedLanguage = lang; notifyListeners();
          String safeLang = (lang == "台語") ? "tw" : "zh";
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/tts_play_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');
          await file.writeAsBytes(audioBytes, flush: true);
          await Future.delayed(const Duration(milliseconds: 150));
          if (_isDisposed || sessionId != currentPlaySessionId) return;
          await audioPlayer.play(DeviceFileSource(file.path));
          await Future.delayed(const Duration(milliseconds: 100));
          Duration? duration = await audioPlayer.getDuration();
          int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
          int elapsed = 0;
          while (elapsed < waitMs) {
            if (_isDisposed || sessionId != currentPlaySessionId) { try { await audioPlayer.stop(); } catch (_) {} return; }
            await Future.delayed(const Duration(milliseconds: 100)); elapsed += 100;
          }
        }
      } catch (e) { debugPrint("[交替序列播放異常]: $e"); }
    }
    if (sessionId == currentPlaySessionId && !_isDisposed && isVoiceActiveStatus(chatStatus)) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isDisposed && sessionId == currentPlaySessionId && isVoiceActiveStatus(chatStatus)) voiceManager.startBackgroundWakeWordCycle();
      });
    }
  }

  // 💡 第一輪生圖
  Future<void> _processAudioAndExtractKeywords({String? manualText}) async {
    if (_isDisposed) return;
    String userMessage = manualText ?? "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";
    try {
      if (chatStatus == ChatStatus.dislikeGenerating) {
        await triggerModifiedImageGeneration(userMessage);
      } else {
        final Map<String, dynamic> sceneData = await llmService
            .extractSceneData(userMessage);
        originalKeywords = List<String>.from(sceneData['keywords'] ?? []);
        dynamicScene = sceneData['scene']?.toString() ?? "台灣早期懷舊生活場景";
        dynamicEra = sceneData['era']?.toString() ?? "1980s";
        dynamicLocation = sceneData['location']?.toString() ?? "Taiwan";
        if (_isDisposed) return;
        newKeywords = originalKeywords;
        chatHistory.add({"role": "user", "content": userMessage});
        await triggerImageGeneration();
      }

    } catch (e) {
      if (_isDisposed) return;
      aiGeneratedText = "阿公阿嬤拍謝，我剛才不小心恍神了，可以再跟我說一次嗎？";
      chatStatus = chatStatus == ChatStatus.dislikeGenerating ? ChatStatus.dislikePrepare : ChatStatus.prepare;
      notifyListeners();
      _playAlternatingSequence(aiGeneratedText);
    }
  }

  Future<void> triggerImageGeneration() async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      String prompt = originalKeywords.join("、"); if (prompt.isEmpty) prompt = "懷舊元素";
      final String? imageUrl = await imageService.generateNostalgicImage(scene: "$dynamicScene, 包含關鍵元素: $prompt", era: dynamicEra, location: dynamicLocation);
      if (_isDisposed) return;
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; notifyListeners(); playCurrentContextVoice(selectedLanguage); }
      else throw Exception("生圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.prepare; notifyListeners(); }
  }

  Future<void> triggerModifiedImageGeneration(String modifiedPrompt) async {
    if (_isDisposed) return; await stopAudioSequence();
    try {
      final String? imageUrl = await imageService.editImage(imagePath: currentImageUrl, editInstruction: modifiedPrompt);
      if (_isDisposed) return;
      if (imageUrl != null) { currentImageUrl = imageUrl; chatStatus = ChatStatus.evaluation; notifyListeners(); playCurrentContextVoice(selectedLanguage); }
      else throw Exception("改圖出錯");
    } catch (e) { if (_isDisposed) return; chatStatus = ChatStatus.dislikePrepare; notifyListeners(); }
  }

  @override
  void dispose() { _isDisposed = true; voiceManager.dispose(); stopTimer(); audioPlayer.dispose(); super.dispose(); }
}