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
  introPrepare,
  introRecording,
  introProcessing,
  introNameExtracted,
  introTransition,
  prepare, chatting, keywords, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeKeywords, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeKeywords, likeGenerating,
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
    defaultNegativePrompt: "Simplified Chinese, deformed strokes, extra strokes, missing strokes, broken characters, typos, gibberish, illegible text, messy scribbles, distorted text, blurred text, worst quality, low resolution, bad anatomy, watermark, signature",
  );

  final VoiceAssistantManager voiceManager = VoiceAssistantManager();
  final AudioPlayer audioPlayer = AudioPlayer();

  ChatStatus chatStatus = ChatStatus.introPrepare;
  bool _isDisposed = false;

  List<String> elderNames = [];
  String currentElderName = "";

  String aiGeneratedText = "";
  String selectedLanguage = "台語";
  bool isLoading = false;
  bool isExtractingKeywords = false;

  int recordSeconds = 0;
  Timer? recordTimer;

  String accumulatedChatText = "";
  bool isProcessingEnd = false;

  final int maxKeywordLength = 5;
  List<String> originalKeywords = [];
  List<String> newKeywords = [];
  final List<Map<String, String>> chatHistory = [];

  String currentImageUrl = "";
  String dynamicScene = "台灣早期懷舊生活場景";
  String dynamicEra = "1980s";
  String dynamicLocation = "Taiwan";

  int currentPlaySessionId = 0;

  bool isVoiceActiveStatus(ChatStatus status) {
    return status == ChatStatus.prepare || status == ChatStatus.chatting || status == ChatStatus.keywords ||
        status == ChatStatus.dislikePrepare || status == ChatStatus.dislikeChatting || status == ChatStatus.dislikeKeywords ||
        status == ChatStatus.likePrepare || status == ChatStatus.likeChatting || status == ChatStatus.likeKeywords;
  }

  Future<void> init() async {
    await ReminiCareConfig.loadConfig();

    voiceManager.onStartChatFlow = triggerStartChatFlow;
    voiceManager.onRestartChatFlow = triggerStartChatFlow;
    voiceManager.onEndChatFlow = () async {
      if (_isIntroStatus()) {
        debugPrint("⚠️ [控制器] 目前在自我介紹階段，拒絕誤觸「結束聊天」口令！");
        return;
      }
      _setKeywordsState();
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

    voiceManager.onBackgroundTextRecognized = (text) {
      _handleBackgroundCommands(text);
    };

    voiceManager.startBackgroundWakeWordCycle();
    notifyListeners();
  }

  bool _isIntroStatus() {
    return chatStatus == ChatStatus.introPrepare ||
        chatStatus == ChatStatus.introRecording ||
        chatStatus == ChatStatus.introProcessing ||
        chatStatus == ChatStatus.introNameExtracted ||
        chatStatus == ChatStatus.introTransition;
  }

  void _handleBackgroundCommands(String text) {
    if (chatStatus == ChatStatus.introPrepare && text.contains("開始介紹")) {
      startIntroRecording();
    } else if (chatStatus == ChatStatus.introNameExtracted) {
      if (text.contains("下一位")) {
        nextPersonIntro();
      } else if (text.contains("結束介紹")) {
        finishIntro();
      }
    }
  }

  void startIntroRecording() async {
    await stopAudioSequence();
    chatStatus = ChatStatus.introRecording;
    notifyListeners();
    voiceManager.startChatFlow();
  }

  void stopIntroRecordingManually() async {
    await voiceManager.forceEndChat();
  }

  Future<void> _handleIntroSpeechCompleted(List<String> paths) async {
    if (paths.isEmpty) {
      chatStatus = ChatStatus.introPrepare;
      notifyListeners();
      return;
    }

    chatStatus = ChatStatus.introProcessing;
    notifyListeners();

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (_) {}
      if (t != null && t.trim().isNotEmpty) {
        chunkText += t;
      }
    }

    if (chunkText.isNotEmpty) {
      String prompt = "請從以下自我介紹中擷取出長輩的名字或稱呼（例如：王阿嬤、李爺爺、阿公等）。如果沒有提到名字，請回傳「無名氏」。除了名字之外，不要回傳任何其他字。\n自我介紹內容：「$chunkText」";
      try {
        currentElderName = await llmService.generateChatReply(prompt, []);
      } catch (e) {
        currentElderName = "長輩";
      }
    } else {
      currentElderName = "無名氏";
    }

    chatStatus = ChatStatus.introNameExtracted;
    voiceManager.startBackgroundWakeWordCycle();
    notifyListeners();
  }

  void nextPersonIntro() {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") {
      elderNames.add(currentElderName);
    }
    currentElderName = "";
    chatStatus = ChatStatus.introPrepare;
    voiceManager.startBackgroundWakeWordCycle();
    notifyListeners();
  }

  Future<void> finishIntro() async {
    if (currentElderName.isNotEmpty && currentElderName != "無名氏" && currentElderName != "長輩") {
      elderNames.add(currentElderName);
    }
    await voiceManager.stopActiveAudioOperations();

    chatStatus = ChatStatus.introTransition;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 3));

    chatStatus = ChatStatus.prepare;
    await fetchInitialQuestion();
    voiceManager.checkCompletedCommands = false;
    voiceManager.startBackgroundWakeWordCycle();
    notifyListeners();
  }

  void startTimer() {
    recordTimer?.cancel();
    recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      recordSeconds++;
      notifyListeners();

      int maxRecordLimit = int.parse(ReminiCareConfig.maxRecordLimit);
      if (recordSeconds >= maxRecordLimit) {
        debugPrint("⏳ [錄音限時] 自動停止錄製以防偏題！");
        handleEndChat();
      }
    });
  }

  void stopTimer() {
    recordTimer?.cancel();
    recordTimer = null;
  }

  Future<void> stopAudioSequence() async {
    currentPlaySessionId++;
    try { await audioPlayer.stop(); } catch (_) {}
  }

  void _setKeywordsState() {
    if (chatStatus == ChatStatus.dislikeChatting || chatStatus == ChatStatus.dislikePrepare) {
      chatStatus = ChatStatus.dislikeKeywords;
    } else if (chatStatus == ChatStatus.likeChatting || chatStatus == ChatStatus.likePrepare) {
      chatStatus = ChatStatus.likeKeywords;
    } else {
      chatStatus = ChatStatus.keywords;
    }
    notifyListeners();
  }

  void triggerStartChatFlow() async {
    if (_isIntroStatus()) {
      debugPrint("⚠️ [控制器] 目前在自我介紹階段，拒絕誤觸開始聊天口令！");
      return;
    }

    stopAudioSequence();
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 600));

    if (chatStatus == ChatStatus.dislikePrepare || chatStatus == ChatStatus.dislikeKeywords) {
      chatStatus = ChatStatus.dislikeChatting;
    } else if (chatStatus == ChatStatus.likePrepare || chatStatus == ChatStatus.likeKeywords) {
      chatStatus = ChatStatus.likeChatting;
    } else {
      chatStatus = ChatStatus.chatting;
    }

    recordSeconds = 0;
    accumulatedChatText = "";
    isProcessingEnd = false;
    startTimer();
    notifyListeners();

    voiceManager.startChatFlow();
  }

  Future<void> handleEndChat() async {
    isProcessingEnd = true;
    stopTimer();

    if (_isDisposed) return;
    if (chatStatus == ChatStatus.dislikeChatting) {
      chatStatus = ChatStatus.dislikeGenerating;
    } else if (chatStatus == ChatStatus.likeChatting) {
      chatStatus = ChatStatus.likeGenerating;
    } else {
      chatStatus = ChatStatus.generating;
    }
    notifyListeners();

    await voiceManager.forceEndChat();
  }

  Future<void> _handleVadChunk(List<String> paths) async {
    bool isChatting = chatStatus == ChatStatus.chatting ||
        chatStatus == ChatStatus.dislikeChatting ||
        chatStatus == ChatStatus.likeChatting;

    if (!isProcessingEnd && isChatting) voiceManager.startChatFlow();
    if (paths.isEmpty) return;

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (_) {}
      if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
    }

    if (chunkText.isEmpty) return;
    if (isProcessingEnd) {
      accumulatedChatText += chunkText;
      return;
    }

    bool isEnd = false;
    String cleanText = chunkText.replaceAll(" ", "");
    for (String cmd in ReminiCareConfig.endWakeWords) {
      if (cleanText.contains(cmd)) { isEnd = true; break; }
    }

    if (isEnd) {
      isProcessingEnd = true;
      stopTimer();
      await voiceManager.stopActiveAudioOperations();

      if (chatStatus == ChatStatus.dislikeChatting) {
        chatStatus = ChatStatus.dislikeGenerating;
      } else if (chatStatus == ChatStatus.likeChatting) {
        chatStatus = ChatStatus.likeGenerating;
      } else {
        chatStatus = ChatStatus.generating;
      }
      notifyListeners();

      accumulatedChatText += chunkText;
      String cleanTextForLLM = accumulatedChatText;
      for (String cmd in ReminiCareConfig.endWakeWords) {
        cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
      }

      _processAudioAndExtractKeywords(manualText: cleanTextForLLM);
    } else {
      accumulatedChatText += chunkText;
      debugPrint("💬 [VAD 自動分段擷取]: $chunkText -> 總累積: $accumulatedChatText");
    }
  }

  Future<void> handleFinalChunk(List<String> paths) async {
    String chunkText = "";
    if (paths.isNotEmpty) {
      for (String path in paths) {
        String? t = await sttService.transcribe(path);
        try { File(path).deleteSync(); } catch (e) {}
        if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
      }
    }
    accumulatedChatText += chunkText;
    debugPrint("🏁 [手動/超時結束] 最終彙整內容: $accumulatedChatText");

    String cleanTextForLLM = accumulatedChatText;
    for (String cmd in ReminiCareConfig.endWakeWords) {
      cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
    }

    _processAudioAndExtractKeywords(manualText: cleanTextForLLM);
  }

  Future<void> fetchInitialQuestion() async {
    if (_isDisposed) return;
    isLoading = true;
    notifyListeners();
    try {
      String participants = elderNames.isNotEmpty ? "今天參與的長輩有：${elderNames.join('、')}。" : "";
      aiGeneratedText = await llmService.generateInitialQuestion();
    } catch (e) {
      aiGeneratedText = "哈囉！小時候家裡最常吃什麼呢？";
    } finally {
      if (!_isDisposed) {
        isLoading = false;
        notifyListeners();
        playCurrentContextVoice(selectedLanguage);
      }
    }
  }

  Future<void> handleLikeAndGenerateExtension() async {
    if (_isDisposed) return;
    isLoading = true;
    chatStatus = ChatStatus.likePrepare;
    notifyListeners();

    try {
      String previousQuestion = aiGeneratedText;
      String lastUserMessage = "";

      for (var msg in chatHistory.reversed) {
        if (msg['role'] == 'user') {
          lastUserMessage = msg['content'] ?? "";
          break;
        }
      }

      if (lastUserMessage.isEmpty) {
        lastUserMessage = accumulatedChatText;
      }

      final String extendedQuestion = await llmService.generateExtendedQuestion(previousQuestion, lastUserMessage);
      aiGeneratedText = extendedQuestion;
    } catch (e) {
      debugPrint("[NVIDIA] 延伸問題生成發生錯誤: $e");
      aiGeneratedText = "這張照片有讓您想起更多小時候的趣味往事嗎？";
    } finally {
      if (!_isDisposed) {
        isLoading = false;
        // 💡 修正：不再自動呼叫 triggerStartChatFlow，讓權杖停留在 Prepare 狀態
        voiceManager.checkCompletedCommands = false;
        voiceManager.startBackgroundWakeWordCycle();
        notifyListeners();
        _playAlternatingSequence(aiGeneratedText);
      }
    }
  }

  void playCurrentContextVoice(String lang) {
    if (_isDisposed) return;
    String textToPlay = aiGeneratedText;
    if (chatStatus == ChatStatus.evaluation || chatStatus == ChatStatus.dislikeEvaluation) {
      textToPlay = "這張圖符合您的回憶嗎？";
    } else if (chatStatus == ChatStatus.dislikePrepare) {
      textToPlay = "哪裡不對？";
    } else if (chatStatus == ChatStatus.likePrepare || chatStatus == ChatStatus.likeChatting) {
      textToPlay = aiGeneratedText;
    }
    _playSingleVoice(textToPlay, lang);
  }

  Future<void> _playSingleVoice(String text, String language) async {
    await stopAudioSequence();
    await voiceManager.stopActiveAudioOperations();

    if (text.isEmpty || kIsWeb) return;

    final sessionId = currentPlaySessionId;

    try {
      selectedLanguage = language;
      notifyListeners();

      final Uint8List? audioBytes = await ttsService.generateSpeech(text, language);
      if (audioBytes != null) {
        if (_isDisposed || sessionId != currentPlaySessionId) return;

        String safeLang = (language == "台語") ? "tw" : "zh";
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/tts_single_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');
        await file.writeAsBytes(audioBytes, flush: true);

        await Future.delayed(const Duration(milliseconds: 150));

        if (_isDisposed || sessionId != currentPlaySessionId) {
          try { file.deleteSync(); } catch (_) {}
          return;
        }

        await audioPlayer.play(DeviceFileSource(file.path));

        await Future.delayed(const Duration(milliseconds: 100));
        Duration? duration = await audioPlayer.getDuration();

        int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
        int elapsed = 0;

        while (elapsed < waitMs) {
          if (_isDisposed || sessionId != currentPlaySessionId) {
            try { await audioPlayer.stop(); } catch (_) {}
            try { file.deleteSync(); } catch (_) {}
            return;
          }
          await Future.delayed(const Duration(milliseconds: 100));
          elapsed += 100;
        }

        if (sessionId == currentPlaySessionId) {
          try { await audioPlayer.stop(); } catch (_) {}
        }
        try { file.deleteSync(); } catch (_) {}
      }
    } catch (e) {
      debugPrint("[單次播放錯誤]: $e");
    } finally {
      if (sessionId == currentPlaySessionId && !_isDisposed) {
        if (isVoiceActiveStatus(chatStatus)) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_isDisposed && sessionId == currentPlaySessionId && isVoiceActiveStatus(chatStatus)) {
              // 💡 播完單次語音後，讓系統進入背景聆聽口令（開始聊天）
              voiceManager.startBackgroundWakeWordCycle();
            }
          });
        }
      }
    }
  }

  Future<void> _playAlternatingSequence(String text) async {
    await stopAudioSequence();
    await voiceManager.stopActiveAudioOperations();

    if (text.isEmpty || kIsWeb) return;

    final sessionId = currentPlaySessionId;
    final sequence = ["台語", "中文", "台語", "中文"];
    final Map<String, Uint8List> localTtsCacheBytes = {};

    for (final lang in sequence) {
      if (_isDisposed || sessionId != currentPlaySessionId) return;

      try {
        Uint8List? audioBytes;

        if (localTtsCacheBytes.containsKey(lang)) {
          audioBytes = localTtsCacheBytes[lang];
        } else {
          audioBytes = await ttsService.generateSpeech(text, lang);
          if (audioBytes != null) {
            localTtsCacheBytes[lang] = audioBytes;
          }
        }

        if (audioBytes != null && !_isDisposed && sessionId == currentPlaySessionId) {
          selectedLanguage = lang;
          notifyListeners();

          String safeLang = (lang == "台語") ? "tw" : "zh";
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/tts_play_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');

          await file.writeAsBytes(audioBytes, flush: true);
          await Future.delayed(const Duration(milliseconds: 150));

          if (_isDisposed || sessionId != currentPlaySessionId) {
            try { file.deleteSync(); } catch (_) {}
            return;
          }

          await audioPlayer.play(DeviceFileSource(file.path));

          await Future.delayed(const Duration(milliseconds: 100));
          Duration? duration = await audioPlayer.getDuration();

          int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
          int elapsed = 0;

          while (elapsed < waitMs) {
            if (_isDisposed || sessionId != currentPlaySessionId) {
              try { await audioPlayer.stop(); } catch (_) {}
              try { file.deleteSync(); } catch (_) {}
              return;
            }
            await Future.delayed(const Duration(milliseconds: 100));
            elapsed += 100;
          }

          if (sessionId == currentPlaySessionId) {
            try { await audioPlayer.stop(); } catch (_) {}
          }
          try { file.deleteSync(); } catch (_) {}
        }
      } catch (e) {
        debugPrint("[交替序列播放異常]: $e");
      }
    }

    if (sessionId == currentPlaySessionId && !_isDisposed) {
      if (isVoiceActiveStatus(chatStatus)) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_isDisposed && sessionId == currentPlaySessionId && isVoiceActiveStatus(chatStatus)) {
            // 💡 修正：不再自動觸發錄音，而是退回背景監聽口令
            voiceManager.startBackgroundWakeWordCycle();
          }
        });
      }
    }
  }

  Future<void> _processAudioAndExtractKeywords({String? manualText}) async {
    if (_isDisposed) return;

    String userMessage = manualText ?? "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";

    try {
      debugPrint("💬 [開始提取關鍵字]: $userMessage");

      final Map<String, dynamic> sceneData = await llmService.extractSceneData(userMessage);

      originalKeywords = List<String>.from(sceneData['keywords'] ?? []);
      dynamicScene = sceneData['scene']?.toString() ?? "台灣早期懷舊生活場景";
      dynamicEra = sceneData['era']?.toString() ?? "1980s";
      dynamicLocation = sceneData['location']?.toString() ?? "Taiwan";

      if (_isDisposed) return;

      newKeywords = originalKeywords;
      chatHistory.add({"role": "user", "content": userMessage});

      if (chatStatus == ChatStatus.dislikeGenerating) {
        await triggerModifiedImageGeneration();
      } else if (chatStatus == ChatStatus.likeGenerating) {
        await triggerLikeExtendedImageGeneration();
      } else {
        await triggerImageGeneration();
      }

    } catch (e) {
      debugPrint("關鍵字擷取發生錯誤: $e");
      if (_isDisposed) return;

      aiGeneratedText = "阿公阿嬤拍謝，我剛才不小心恍神了，可以再跟我說一次嗎？";
      if (chatStatus == ChatStatus.dislikeGenerating) {
        chatStatus = ChatStatus.dislikePrepare;
      } else if (chatStatus == ChatStatus.likeGenerating) {
        chatStatus = ChatStatus.likePrepare;
      } else {
        chatStatus = ChatStatus.prepare;
      }
      notifyListeners();
      _playAlternatingSequence(aiGeneratedText);
    }
  }

  Future<void> triggerImageGeneration() async {
    if (_isDisposed) return;

    chatStatus = ChatStatus.generating;
    notifyListeners();
    await stopAudioSequence();

    try {
      String prompt = originalKeywords.join("、");
      if (prompt.isEmpty) prompt = "懷舊元素";

      final String? imageUrl = await imageService.generateNostalgicImage(
        scene: "$dynamicScene, 包含關鍵元素: $prompt",
        era: dynamicEra,
        location: dynamicLocation,
      );

      if (_isDisposed) return;
      if (imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.evaluation;
        notifyListeners();
        playCurrentContextVoice(selectedLanguage);
      } else {
        throw Exception("生圖出錯");
      }
    } catch (e) {
      if (_isDisposed) return;
      chatStatus = ChatStatus.prepare;
      notifyListeners();
    }
  }

  Future<void> triggerModifiedImageGeneration() async {
    if (_isDisposed) return;

    chatStatus = ChatStatus.dislikeGenerating;
    notifyListeners();
    await stopAudioSequence();

    try {
      String combinedPrompt = newKeywords.join("、");
      if (combinedPrompt.isEmpty) combinedPrompt = "修改後的食物與場景";

      final String? imageUrl = await imageService.editImage(
        imagePath: currentImageUrl,
        editInstruction: "在 $dynamicScene 的大場景氛圍下, 將細節修改或新增為: $combinedPrompt",
      );

      if (_isDisposed) return;
      if (imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.dislikeEvaluation;
        notifyListeners();
        playCurrentContextVoice(selectedLanguage);
      } else {
        throw Exception("改圖出錯");
      }
    } catch (e) {
      if (_isDisposed) return;
      chatStatus = ChatStatus.dislikePrepare;
      notifyListeners();
    }
  }

  Future<void> triggerLikeExtendedImageGeneration() async {
    if (_isDisposed) return;

    chatStatus = ChatStatus.likeGenerating;
    notifyListeners();
    await stopAudioSequence();

    try {
      String combinedPrompt = [...originalKeywords, ...newKeywords].join("、");

      final String? imageUrl = await imageService.generateNostalgicImage(
        scene: "$dynamicScene, 包含關鍵元素: $combinedPrompt",
        era: dynamicEra,
        location: dynamicLocation,
      );

      if (_isDisposed) return;
      if (imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.evaluation;
        notifyListeners();
        playCurrentContextVoice(selectedLanguage);
      } else {
        throw Exception("延伸話題生圖出錯");
      }
    } catch (e) {
      if (_isDisposed) return;
      chatStatus = ChatStatus.likePrepare;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    voiceManager.dispose();
    stopTimer();
    audioPlayer.dispose();
    super.dispose();
  }
}