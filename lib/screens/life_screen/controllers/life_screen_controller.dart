import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'package:remini_care_ai_app/services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/nvidia_llm_service.dart';
import 'package:remini_care_ai_app/services/speech_services.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

// =========================================================================
// 💡 定義聊天狀態列舉
// =========================================================================
enum ChatStatus {
  prepare, chatting, completed, keywords, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeCompleted, dislikeKeywords, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeCompleted, likeKeywords, likeGenerating,
}

// =========================================================================
// 🧠 LifeScreenController: 專責處理所有生命故事的業務邏輯與狀態管理
// =========================================================================
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

  // 💡 開放給 UI 讀取的狀態 (原本在 State 裡的變數)
  String aiGeneratedText = "";
  String selectedLanguage = "台語";
  ChatStatus chatStatus = ChatStatus.prepare;

  bool isLoading = true;
  bool isExtractingKeywords = false;
  int recordSeconds = 0;

  final int maxKeywordLength = 5;
  List<String> originalKeywords = [];
  List<String> newKeywords = [];
  String currentImageUrl = "";

  // 內部邏輯變數
  Timer? _recordTimer;
  String _accumulatedChatText = "";
  bool _isProcessingEnd = false;
  final List<Map<String, String>> _chatHistory = [];

  String _dynamicScene = "台灣早期懷舊生活場景";
  String _dynamicEra = "1980s";
  String _dynamicLocation = "Taiwan";

  int _currentPlaySessionId = 0;
  bool _isDisposed = false;

  Future<void> init() async {
    await ReminiCareConfig.loadConfig();
    if (_isDisposed) return;

    fetchInitialQuestion();

    // 💡 綁定 VoiceManager 的回調事件
    voiceManager.onStartChatFlow = () => triggerStartChatFlow();
    voiceManager.onRestartChatFlow = () => triggerStartChatFlow();

    voiceManager.onEndChatFlow = () async {
      if (_isDisposed) return;
      if (chatStatus == ChatStatus.dislikeCompleted) {
        chatStatus = ChatStatus.dislikeKeywords;
      } else if (chatStatus == ChatStatus.likeCompleted) {
        chatStatus = ChatStatus.likeKeywords;
      } else {
        chatStatus = ChatStatus.keywords;
      }
      notifyListeners();
      await stopAudioSequence();
      await voiceManager.stopActiveAudioOperations();
    };

    voiceManager.onSpeechCompleted = (mergedWavPaths) {
      if (_isProcessingEnd) {
        _handleFinalChunk(mergedWavPaths ?? []);
      } else {
        _handleVadChunk(mergedWavPaths ?? []);
      }
    };

    voiceManager.startBackgroundWakeWordCycle();
  }

  @override
  void dispose() {
    _isDisposed = true;
    voiceManager.dispose();
    _stopTimer();
    audioPlayer.dispose();
    super.dispose();
  }

  void _startTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      recordSeconds++;
      notifyListeners();

      int maxRecordLimit = int.parse(ReminiCareConfig.maxRecordLimit);
      if (recordSeconds >= maxRecordLimit) {
        debugPrint("⏳ [錄音限時] 已達 $maxRecordLimit 秒極限，系統自動停止錄製！");
        handleEndChat();
      }
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void resetAllStates() async {
    if (_isDisposed) return;
    chatStatus = ChatStatus.prepare;
    recordSeconds = 0;
    _accumulatedChatText = "";
    _isProcessingEnd = false;
    currentImageUrl = "";
    originalKeywords.clear();
    newKeywords.clear();
    _chatHistory.clear();
    aiGeneratedText = "";
    _dynamicScene = "台灣早期懷舊生活場景";
    _dynamicEra = "1980s";
    _dynamicLocation = "Taiwan";
    isLoading = true;
    _stopTimer();
    notifyListeners();

    await stopAudioSequence();
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 300));

    await voiceManager.stopActiveAudioOperations();
    voiceManager.checkCompletedCommands = false;
    fetchInitialQuestion();
    voiceManager.startBackgroundWakeWordCycle();
  }

  bool isVoiceActiveStatus() {
    return chatStatus == ChatStatus.prepare ||
        chatStatus == ChatStatus.chatting ||
        chatStatus == ChatStatus.completed ||
        chatStatus == ChatStatus.dislikePrepare ||
        chatStatus == ChatStatus.dislikeChatting ||
        chatStatus == ChatStatus.dislikeCompleted ||
        chatStatus == ChatStatus.likePrepare ||
        chatStatus == ChatStatus.likeChatting ||
        chatStatus == ChatStatus.likeCompleted;
  }

  Future<void> stopAudioSequence() async {
    _currentPlaySessionId++;
    try { await audioPlayer.stop(); } catch (_) {}
  }

  Future<void> _playAlternatingSequence(String text) async {
    await stopAudioSequence();
    await voiceManager.stopActiveAudioOperations();

    if (text.isEmpty || kIsWeb) return;

    final sessionId = _currentPlaySessionId;
    final sequence = ["台語", "中文", "台語", "中文"];
    final Map<String, Uint8List> localTtsCacheBytes = {};

    for (final lang in sequence) {
      if (_isDisposed || sessionId != _currentPlaySessionId) return;

      try {
        Uint8List? audioBytes;
        if (localTtsCacheBytes.containsKey(lang)) {
          audioBytes = localTtsCacheBytes[lang];
        } else {
          audioBytes = await ttsService.generateSpeech(text, lang);
          if (audioBytes != null) localTtsCacheBytes[lang] = audioBytes;
        }

        if (audioBytes != null && !_isDisposed && sessionId == _currentPlaySessionId) {
          selectedLanguage = lang;
          notifyListeners();

          String safeLang = (lang == "台語") ? "tw" : "zh";
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/tts_play_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');

          await file.writeAsBytes(audioBytes, flush: true);
          await Future.delayed(const Duration(milliseconds: 150));

          if (_isDisposed || sessionId != _currentPlaySessionId) {
            try { file.deleteSync(); } catch (_) {}
            return;
          }

          await audioPlayer.play(DeviceFileSource(file.path));
          await Future.delayed(const Duration(milliseconds: 100));
          Duration? duration = await audioPlayer.getDuration();

          int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
          int elapsed = 0;

          while (elapsed < waitMs) {
            if (_isDisposed || sessionId != _currentPlaySessionId) {
              try { await audioPlayer.stop(); } catch (_) {}
              try { file.deleteSync(); } catch (_) {}
              return;
            }
            await Future.delayed(const Duration(milliseconds: 100));
            elapsed += 100;
          }

          if (sessionId == _currentPlaySessionId) {
            try { await audioPlayer.stop(); } catch (_) {}
          }
          try { file.deleteSync(); } catch (_) {}
        }
      } catch (e) {
        debugPrint("[交替序列播放異常]: $e");
      }
    }

    if (sessionId == _currentPlaySessionId && !_isDisposed && isVoiceActiveStatus()) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isDisposed && sessionId == _currentPlaySessionId && isVoiceActiveStatus()) {
          voiceManager.startBackgroundWakeWordCycle();
        }
      });
    }
  }

  void _triggerCurrentContextSequencePlayback() {
    String textToPlay = aiGeneratedText;
    if (chatStatus == ChatStatus.evaluation || chatStatus == ChatStatus.dislikeEvaluation) {
      textToPlay = "這張圖符合您的回憶嗎？";
    } else if (chatStatus == ChatStatus.dislikePrepare) {
      textToPlay = "哪裡不對？";
    } else if (chatStatus == ChatStatus.likePrepare) {
      textToPlay = "這張圖片讓您想到什麼？";
    }
    _playAlternatingSequence(textToPlay);
  }

  Future<void> playSingleVoice(String text, String language) async {
    await stopAudioSequence();
    await voiceManager.stopActiveAudioOperations();

    if (text.isEmpty || kIsWeb) return;
    final sessionId = _currentPlaySessionId;

    try {
      selectedLanguage = language;
      notifyListeners();

      final Uint8List? audioBytes = await ttsService.generateSpeech(text, language);
      if (audioBytes != null && !_isDisposed && sessionId == _currentPlaySessionId) {
        String safeLang = (language == "台語") ? "tw" : "zh";
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/tts_single_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');
        await file.writeAsBytes(audioBytes, flush: true);

        await Future.delayed(const Duration(milliseconds: 150));

        if (_isDisposed || sessionId != _currentPlaySessionId) {
          try { file.deleteSync(); } catch (_) {}
          return;
        }

        await audioPlayer.play(DeviceFileSource(file.path));
        await Future.delayed(const Duration(milliseconds: 100));
        Duration? duration = await audioPlayer.getDuration();

        int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
        int elapsed = 0;

        while (elapsed < waitMs) {
          if (_isDisposed || sessionId != _currentPlaySessionId) {
            try { await audioPlayer.stop(); } catch (_) {}
            try { file.deleteSync(); } catch (_) {}
            return;
          }
          await Future.delayed(const Duration(milliseconds: 100));
          elapsed += 100;
        }

        if (sessionId == _currentPlaySessionId) try { await audioPlayer.stop(); } catch (_) {}
        try { file.deleteSync(); } catch (_) {}
      }
    } catch (e) {
      debugPrint("[單次播放錯誤]: $e");
    } finally {
      if (sessionId == _currentPlaySessionId && !_isDisposed && isVoiceActiveStatus()) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_isDisposed && sessionId == _currentPlaySessionId && isVoiceActiveStatus()) {
            voiceManager.startBackgroundWakeWordCycle();
          }
        });
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
    } else if (chatStatus == ChatStatus.likePrepare) {
      textToPlay = "這張圖片讓您想到什麼？";
    }
    playSingleVoice(textToPlay, lang);
  }

  void triggerStartChatFlow() async {
    stopAudioSequence();
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 600));

    if (chatStatus == ChatStatus.dislikePrepare || chatStatus == ChatStatus.dislikeCompleted) {
      chatStatus = ChatStatus.dislikeChatting;
    } else if (chatStatus == ChatStatus.likePrepare || chatStatus == ChatStatus.likeCompleted) {
      chatStatus = ChatStatus.likeChatting;
    } else {
      chatStatus = ChatStatus.chatting;
    }

    recordSeconds = 0;
    _accumulatedChatText = "";
    _isProcessingEnd = false;
    _startTimer();
    notifyListeners();

    voiceManager.startChatFlow();
  }

  Future<void> handleEndChat() async {
    _isProcessingEnd = true;
    _stopTimer();

    if (chatStatus == ChatStatus.dislikeChatting) chatStatus = ChatStatus.dislikeCompleted;
    else if (chatStatus == ChatStatus.likeChatting) chatStatus = ChatStatus.likeCompleted;
    else chatStatus = ChatStatus.completed;

    notifyListeners();
    await voiceManager.forceEndChat();
  }

  Future<void> _handleVadChunk(List<String> paths) async {
    bool isChatting = chatStatus == ChatStatus.chatting ||
        chatStatus == ChatStatus.dislikeChatting ||
        chatStatus == ChatStatus.likeChatting;

    if (!_isProcessingEnd && isChatting) voiceManager.startChatFlow();
    if (paths.isEmpty) return;

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (_) {}
      if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
    }

    if (chunkText.isEmpty) return;
    if (_isProcessingEnd) {
      _accumulatedChatText += chunkText;
      return;
    }

    bool isEnd = false;
    String cleanText = chunkText.replaceAll(" ", "");
    for (String cmd in ReminiCareConfig.endWakeWords) {
      if (cleanText.contains(cmd)) { isEnd = true; break; }
    }

    if (isEnd) {
      _isProcessingEnd = true;
      _stopTimer();
      await voiceManager.stopActiveAudioOperations();

      if (chatStatus == ChatStatus.dislikeChatting) chatStatus = ChatStatus.dislikeCompleted;
      else if (chatStatus == ChatStatus.likeChatting) chatStatus = ChatStatus.likeCompleted;
      else chatStatus = ChatStatus.completed;
      notifyListeners();

      _accumulatedChatText += chunkText;
      String cleanTextForLLM = _accumulatedChatText;
      for (String cmd in ReminiCareConfig.endWakeWords) {
        cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
      }

      processAudioAndChat(manualText: cleanTextForLLM);
      voiceManager.checkCompletedCommands = true;
      voiceManager.startBackgroundWakeWordCycle();
    } else {
      _accumulatedChatText += chunkText;
      debugPrint("💬 [VAD 累積]: $_accumulatedChatText");
    }
  }

  Future<void> _handleFinalChunk(List<String> paths) async {
    String chunkText = "";
    if (paths.isNotEmpty) {
      for (String path in paths) {
        String? t = await sttService.transcribe(path);
        try { File(path).deleteSync(); } catch (_) {}
        if (t != null && t.trim().isNotEmpty) chunkText += t + "，";
      }
    }

    _accumulatedChatText += chunkText;
    String cleanTextForLLM = _accumulatedChatText;
    for (String cmd in ReminiCareConfig.endWakeWords) {
      cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
    }

    processAudioAndChat(manualText: cleanTextForLLM);
    voiceManager.checkCompletedCommands = true;
    voiceManager.startBackgroundWakeWordCycle();
  }

  Future<void> fetchInitialQuestion() async {
    isLoading = true;
    notifyListeners();
    try {
      aiGeneratedText = await llmService.generateInitialQuestion();
    } catch (e) {
      aiGeneratedText = "哈囉！小時候家裡最常吃什麼呢？";
    } finally {
      if (!_isDisposed) {
        isLoading = false;
        notifyListeners();
        _triggerCurrentContextSequencePlayback();
      }
    }
  }

  Future<void> processAudioAndChat({String? manualText}) async {
    isExtractingKeywords = true;
    notifyListeners();
    String userMessage = manualText ?? "";

    try {
      if (userMessage.isEmpty) {
        if (chatStatus == ChatStatus.completed) userMessage = "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";
        else if (chatStatus == ChatStatus.dislikeCompleted) userMessage = "這張不像啦，桌上只有一鍋蕃薯粥配醃蘿蔔而已。";
        else userMessage = "兄弟姊妹都會去山上摸魚。";
      }

      final String reply = await llmService.generateChatReply(userMessage, _chatHistory);
      final Map<String, dynamic> sceneData = await llmService.extractSceneData(userMessage);

      final List<String> extracted = List<String>.from(sceneData['keywords'] ?? []);
      _dynamicScene = sceneData['scene']?.toString() ?? "台灣早期懷舊生活場景";
      _dynamicEra = sceneData['era']?.toString() ?? "1980s";
      _dynamicLocation = sceneData['location']?.toString() ?? "Taiwan";

      aiGeneratedText = reply;
      if (chatStatus == ChatStatus.completed || chatStatus == ChatStatus.keywords) {
        originalKeywords = extracted;
      } else {
        newKeywords = extracted;
      }

      _chatHistory.add({"role": "user", "content": userMessage});
      _chatHistory.add({"role": "assistant", "content": reply});

      _triggerCurrentContextSequencePlayback();
    } catch (e) {
      aiGeneratedText = "阿公阿嬤拍謝，我剛才不小心恍神了，可以再跟我說一次嗎？";
      _triggerCurrentContextSequencePlayback();
    } finally {
      if (!_isDisposed) {
        isExtractingKeywords = false;
        notifyListeners();
      }
    }
  }

  Future<void> triggerImageGeneration() async {
    chatStatus = ChatStatus.generating;
    notifyListeners();
    await stopAudioSequence();

    try {
      String prompt = originalKeywords.join("、");
      if (prompt.isEmpty) prompt = "懷舊元素";

      final String? imageUrl = await imageService.generateNostalgicImage(
        scene: "$_dynamicScene, 包含關鍵元素: $prompt", era: _dynamicEra, location: _dynamicLocation,
      );

      if (!_isDisposed && imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.evaluation;
        notifyListeners();
        _triggerCurrentContextSequencePlayback();
      } else {
        throw Exception("生圖出錯");
      }
    } catch (e) {
      if (!_isDisposed) {
        chatStatus = ChatStatus.keywords;
        notifyListeners();
      }
    }
  }

  Future<void> triggerModifiedImageGeneration() async {
    chatStatus = ChatStatus.dislikeGenerating;
    notifyListeners();
    await stopAudioSequence();

    try {
      String combinedPrompt = newKeywords.join("、");
      if (combinedPrompt.isEmpty) combinedPrompt = "修改後的食物與場景";

      final String? imageUrl = await imageService.editImage(
        imagePath: currentImageUrl, editInstruction: "在 $_dynamicScene 的大場景氛圍下, 將細節修改或新增為: $combinedPrompt",
      );

      if (!_isDisposed && imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.dislikeEvaluation;
        notifyListeners();
        _triggerCurrentContextSequencePlayback();
      } else {
        throw Exception("改圖出錯");
      }
    } catch (e) {
      if (!_isDisposed) {
        chatStatus = ChatStatus.dislikeKeywords;
        notifyListeners();
      }
    }
  }

  Future<void> triggerLikeExtendedImageGeneration() async {
    chatStatus = ChatStatus.likeGenerating;
    notifyListeners();
    await stopAudioSequence();

    try {
      String combinedPrompt = [...originalKeywords, ...newKeywords].join("、");
      final String? imageUrl = await imageService.generateNostalgicImage(
        scene: "$_dynamicScene, 包含關鍵元素: $combinedPrompt", era: _dynamicEra, location: _dynamicLocation,
      );

      if (!_isDisposed && imageUrl != null) {
        currentImageUrl = imageUrl;
        chatStatus = ChatStatus.evaluation;
        notifyListeners();
        _triggerCurrentContextSequencePlayback();
      } else {
        throw Exception("延伸話題生圖出錯");
      }
    } catch (e) {
      if (!_isDisposed) {
        chatStatus = ChatStatus.likeKeywords;
        notifyListeners();
      }
    }
  }

  // 💡 供 UI 操作狀態的捷徑方法
  void setChatStatusAndNotify(ChatStatus status) {
    chatStatus = status;
    notifyListeners();
  }
}