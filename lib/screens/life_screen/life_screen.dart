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

import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/keywords_view.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';

enum ChatStatus {
  prepare, chatting, completed, keywords, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeCompleted, dislikeKeywords, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeCompleted, likeKeywords, likeGenerating,
}

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  final NvidiaLlmService _llmService = NvidiaLlmService();
  final ITTSService ttsService = YatingSpeechService();
  final ISTTService sttService = YatingSpeechService();

  final UniversalImageService _imageService = UniversalImageService(
    rawBaseUrl: "https://api.siliconflow.com/v1",
    apiKeyProvider: () => ReminiCareConfig.siliconFlowApiKey,
    generationModel: "Qwen/Qwen-Image",
    editModel: "Qwen/Qwen-Image-Edit",
    defaultNegativePrompt: "Simplified Chinese, deformed strokes, extra strokes, missing strokes, broken characters, typos, gibberish, illegible text, messy scribbles, distorted text, blurred text, worst quality, low resolution, bad anatomy, watermark, signature",
  );

  final VoiceAssistantManager _voiceManager = VoiceAssistantManager();

  String _aiGeneratedText = "";
  String _selectedLanguage = "台語";
  ChatStatus _chatStatus = ChatStatus.prepare;

  bool _isLoading = true;
  bool _isExtractingKeywords = false;

  int _recordSeconds = 0;
  Timer? _recordTimer;

  String _accumulatedChatText = "";
  bool _isProcessingEnd = false;

  final int _maxKeywordLength = 5;
  List<String> _originalKeywords = [];
  List<String> _newKeywords = [];

  final List<Map<String, String>> _chatHistory = [];
  String _currentImageUrl = "";

  String _dynamicScene = "台灣早期懷舊生活場景";
  String _dynamicEra = "1980s";
  String _dynamicLocation = "Taiwan";

  final AudioPlayer _audioPlayer = AudioPlayer();
  int _currentPlaySessionId = 0;

  @override
  void initState() {
    super.initState();
    _initializeConfigurationAndLoad();
  }

  Future<void> _initializeConfigurationAndLoad() async {
    await ReminiCareConfig.loadConfig();
    if (!mounted) return;
    _fetchInitialQuestion();

    _voiceManager.onStartChatFlow = () {
      _triggerStartChatFlow();
    };

    _voiceManager.onRestartChatFlow = () {
      _triggerStartChatFlow();
    };

    _voiceManager.onEndChatFlow = () async {
      if (mounted) {
        setState(() {
          if (_chatStatus == ChatStatus.dislikeCompleted) {
            _chatStatus = ChatStatus.dislikeKeywords;
          } else if (_chatStatus == ChatStatus.likeCompleted) {
            _chatStatus = ChatStatus.likeKeywords;
          } else {
            _chatStatus = ChatStatus.keywords;
          }
        });
        await _stopAudioSequence();
        await _voiceManager.stopActiveAudioOperations();
      }
    };

    _voiceManager.onSpeechCompleted = (mergedWavPaths) {
      if (_isProcessingEnd) {
        _handleFinalChunk(mergedWavPaths ?? []);
      } else {
        _handleVadChunk(mergedWavPaths ?? []);
      }
    };

    _voiceManager.startBackgroundWakeWordCycle();
  }

  void _startTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() { _recordSeconds++; });

      int maxRecordLimit = int.parse(ReminiCareConfig.maxRecordLimit);
      if (_recordSeconds >= maxRecordLimit) {
        debugPrint("⏳ [錄音限時] 已達 $maxRecordLimit 秒極限，系統自動停止錄製以防偏題！");
        _handleEndChat();
      }
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void _resetAllStates() async {
    if (!mounted) return;
    setState(() {
      _chatStatus = ChatStatus.prepare;
      _recordSeconds = 0;
      _accumulatedChatText = "";
      _isProcessingEnd = false;
      _currentImageUrl = "";
      _originalKeywords.clear();
      _newKeywords.clear();
      _chatHistory.clear();
      _aiGeneratedText = "";

      _dynamicScene = "台灣早期懷舊生活場景";
      _dynamicEra = "1980s";
      _dynamicLocation = "Taiwan";

      _isLoading = true;
      _stopTimer();
    });

    await _stopAudioSequence();
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 300));

    await _voiceManager.stopActiveAudioOperations();
    _voiceManager.checkCompletedCommands = false;
    _fetchInitialQuestion();
    _voiceManager.startBackgroundWakeWordCycle();
  }

  bool _isVoiceActiveStatus(ChatStatus status) {
    return status == ChatStatus.prepare ||
        status == ChatStatus.chatting ||
        status == ChatStatus.completed ||
        status == ChatStatus.dislikePrepare ||
        status == ChatStatus.dislikeChatting ||
        status == ChatStatus.dislikeCompleted ||
        status == ChatStatus.likePrepare ||
        status == ChatStatus.likeChatting ||
        status == ChatStatus.likeCompleted;
  }

  bool _isCurrentlyChatting() {
    return _chatStatus == ChatStatus.chatting ||
        _chatStatus == ChatStatus.dislikeChatting ||
        _chatStatus == ChatStatus.likeChatting;
  }

  @override
  void dispose() {
    _voiceManager.dispose();
    _stopTimer();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _stopAudioSequence() async {
    _currentPlaySessionId++;
    try { await _audioPlayer.stop(); } catch (_) {}
  }

  Future<void> _playAlternatingSequence(String text) async {
    await _stopAudioSequence();
    await _voiceManager.stopActiveAudioOperations();

    if (text.isEmpty) return;
    if (kIsWeb) return;

    final sessionId = _currentPlaySessionId;
    final sequence = ["台語", "中文", "台語", "中文"];
    final Map<String, Uint8List> localTtsCacheBytes = {};

    for (final lang in sequence) {
      if (!mounted || sessionId != _currentPlaySessionId) return;

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

        if (audioBytes != null && mounted && sessionId == _currentPlaySessionId) {
          setState(() {
            _selectedLanguage = lang;
          });

          String safeLang = (lang == "台語") ? "tw" : "zh";
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/tts_play_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');

          await file.writeAsBytes(audioBytes, flush: true);
          await Future.delayed(const Duration(milliseconds: 150));

          if (!mounted || sessionId != _currentPlaySessionId) {
            try { file.deleteSync(); } catch (_) {}
            return;
          }

          await _audioPlayer.play(DeviceFileSource(file.path));

          await Future.delayed(const Duration(milliseconds: 100));
          Duration? duration = await _audioPlayer.getDuration();

          int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
          int elapsed = 0;

          while (elapsed < waitMs) {
            if (!mounted || sessionId != _currentPlaySessionId) {
              try { await _audioPlayer.stop(); } catch (_) {}
              try { file.deleteSync(); } catch (_) {}
              return;
            }
            await Future.delayed(const Duration(milliseconds: 100));
            elapsed += 100;
          }

          if (sessionId == _currentPlaySessionId) {
            try { await _audioPlayer.stop(); } catch (_) {}
          }
          try { file.deleteSync(); } catch (_) {}
        }
      } catch (e) {
        debugPrint("[交替序列播放異常]: $e");
      }
    }

    if (sessionId == _currentPlaySessionId) {
      if (mounted && _isVoiceActiveStatus(_chatStatus)) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && sessionId == _currentPlaySessionId && _isVoiceActiveStatus(_chatStatus)) {
            // 確保在這些準備狀態下，系統聽的是「開始」口令
            _voiceManager.checkCompletedCommands = false;
            _voiceManager.startBackgroundWakeWordCycle();
          }
        });
      }
    }
  }

  void _triggerCurrentContextSequencePlayback() {
    String textToPlay = _aiGeneratedText;

    if (_chatStatus == ChatStatus.evaluation || _chatStatus == ChatStatus.dislikeEvaluation) {
      textToPlay = "這張圖符合您的回憶嗎？";
    } else if (_chatStatus == ChatStatus.dislikePrepare) {
      textToPlay = "哪裡不對？";
    } else if (_chatStatus == ChatStatus.likePrepare) {
      textToPlay = "這張圖片讓您想到什麼？";
    }

    _playAlternatingSequence(textToPlay);
  }

  void _triggerStartChatFlow() async {
    _stopAudioSequence();

    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 600));
    }

    setState(() {
      if (_chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeCompleted) {
        _chatStatus = ChatStatus.dislikeChatting;
      } else if (_chatStatus == ChatStatus.likePrepare || _chatStatus == ChatStatus.likeCompleted) {
        _chatStatus = ChatStatus.likeChatting;
      } else {
        _chatStatus = ChatStatus.chatting;
      }

      _recordSeconds = 0;
      _accumulatedChatText = "";
      _isProcessingEnd = false; // 確保重置為未結束狀態

      _startTimer();
    });

    _voiceManager.startChatFlow();
  }

  Future<void> _handleEndChat() async {
    // 💡 關鍵修復：先將旗記設為 true，這樣接下來 VAD 結束時就會被導向 _handleFinalChunk
    _isProcessingEnd = true;
    _stopTimer();

    final currentStatus = _chatStatus;
    if (!mounted) return;
    setState(() {
      _chatStatus = currentStatus == ChatStatus.dislikeChatting
          ? ChatStatus.dislikeCompleted
          : currentStatus == ChatStatus.likeChatting
          ? ChatStatus.likeCompleted
          : ChatStatus.completed;
    });

    await _voiceManager.forceEndChat();
  }

  Future<void> _handleVadChunk(List<String> paths) async {
    // 1. 💡 關鍵修復：只要還是 Chatting 狀態，瞬間重啟錄音引擎！
    if (!_isProcessingEnd && _isCurrentlyChatting()) {
      _voiceManager.startChatFlow();
    }

    if (paths.isEmpty) return;

    String chunkText = "";
    for (String path in paths) {
      String? t = await sttService.transcribe(path);
      try { File(path).deleteSync(); } catch (_) {}
      if (t != null && t.trim().isNotEmpty) {
        chunkText += t + "，";
      }
    }

    if (chunkText.isEmpty) return;

    if (_isProcessingEnd) {
      _accumulatedChatText += chunkText;
      return;
    }

    bool isEnd = false;
    String cleanText = chunkText.replaceAll(" ", "");
    for (String cmd in ReminiCareConfig.endWakeWords) {
      if (cleanText.contains(cmd)) {
        isEnd = true;
        break;
      }
    }

    if (isEnd) {
      _isProcessingEnd = true;
      _stopTimer();
      await _voiceManager.stopActiveAudioOperations();

      if (mounted) {
        setState(() {
          if (_chatStatus == ChatStatus.dislikeChatting) _chatStatus = ChatStatus.dislikeCompleted;
          else if (_chatStatus == ChatStatus.likeChatting) _chatStatus = ChatStatus.likeCompleted;
          else _chatStatus = ChatStatus.completed;
        });
      }

      _accumulatedChatText += chunkText;
      debugPrint("🎉 [檢測到結束關鍵字] 最終彙整內容: $_accumulatedChatText");

      String cleanTextForLLM = _accumulatedChatText;
      for (String cmd in ReminiCareConfig.endWakeWords) {
        cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
      }

      _processAudioAndChat(manualText: cleanTextForLLM);
      _voiceManager.checkCompletedCommands = true;
      _voiceManager.startBackgroundWakeWordCycle();
    } else {
      _accumulatedChatText += chunkText;
      debugPrint("💬 [VAD 自動分段擷取]: $chunkText -> 總累積: $_accumulatedChatText");
    }
  }

  Future<void> _handleFinalChunk(List<String> paths) async {
    String chunkText = "";
    if (paths.isNotEmpty) {
      for (String path in paths) {
        String? t = await sttService.transcribe(path);
        try { File(path).deleteSync(); } catch (_) {}
        if (t != null && t.trim().isNotEmpty) {
          chunkText += t + "，";
        }
      }
    }

    _accumulatedChatText += chunkText;
    debugPrint("🏁 [手動/超時結束] 最終彙整內容: $_accumulatedChatText");

    String cleanTextForLLM = _accumulatedChatText;
    for (String cmd in ReminiCareConfig.endWakeWords) {
      cleanTextForLLM = cleanTextForLLM.replaceAll(cmd, "");
    }

    _processAudioAndChat(manualText: cleanTextForLLM);
    _voiceManager.checkCompletedCommands = true;
    _voiceManager.startBackgroundWakeWordCycle();
  }


  Future<void> _playSingleVoice(String text, String language) async {
    await _stopAudioSequence();
    await _voiceManager.stopActiveAudioOperations();

    if (text.isEmpty) return;

    final sessionId = _currentPlaySessionId;

    try {
      if (kIsWeb) return;
      setState(() {
        _selectedLanguage = language;
      });
      final Uint8List? audioBytes = await ttsService.generateSpeech(text, language);
      if (audioBytes != null) {
        if (!mounted || sessionId != _currentPlaySessionId) return;

        String safeLang = (language == "台語") ? "tw" : "zh";
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/tts_single_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav');
        await file.writeAsBytes(audioBytes, flush: true);

        await Future.delayed(const Duration(milliseconds: 150));

        if (!mounted || sessionId != _currentPlaySessionId) {
          try { file.deleteSync(); } catch (_) {}
          return;
        }

        await _audioPlayer.play(DeviceFileSource(file.path));

        await Future.delayed(const Duration(milliseconds: 100));
        Duration? duration = await _audioPlayer.getDuration();

        int waitMs = (duration?.inMilliseconds ?? 4000) + 300;
        int elapsed = 0;

        while (elapsed < waitMs) {
          if (!mounted || sessionId != _currentPlaySessionId) {
            try { await _audioPlayer.stop(); } catch (_) {}
            try { file.deleteSync(); } catch (_) {}
            return;
          }
          await Future.delayed(const Duration(milliseconds: 100));
          elapsed += 100;
        }

        if (sessionId == _currentPlaySessionId) {
          try { await _audioPlayer.stop(); } catch (_) {}
        }
        try { file.deleteSync(); } catch (_) {}
      }
    } catch (e) {
      debugPrint("[單次播放錯誤]: $e");
    } finally {
      if (sessionId == _currentPlaySessionId) {
        if (mounted && _isVoiceActiveStatus(_chatStatus)) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && sessionId == _currentPlaySessionId && _isVoiceActiveStatus(_chatStatus)) {
              // 確保單次播放結束後，喚醒詞的狀態符合當前的對話進度
              _voiceManager.checkCompletedCommands = (_chatStatus == ChatStatus.completed ||
                  _chatStatus == ChatStatus.dislikeCompleted ||
                  _chatStatus == ChatStatus.likeCompleted);
              _voiceManager.startBackgroundWakeWordCycle();
            }
          });
        }
      }
    }
  }

  void _playCurrentContextVoice(String lang) {
    if (!mounted) return;
    String textToPlay = _aiGeneratedText;

    if (_chatStatus == ChatStatus.evaluation || _chatStatus == ChatStatus.dislikeEvaluation) {
      textToPlay = "這張圖符合您的回憶嗎？";
    } else if (_chatStatus == ChatStatus.dislikePrepare) {
      textToPlay = "哪裡不對？";
    } else if (_chatStatus == ChatStatus.likePrepare) {
      textToPlay = "這張圖片讓您想到什麼？";
    }

    _playSingleVoice(textToPlay, lang);
  }

  Future<void> _fetchInitialQuestion() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    try {
      final String question = await _llmService.generateInitialQuestion();
      if (!mounted) return;
      setState(() {
        _aiGeneratedText = question;
      });
      _triggerCurrentContextSequencePlayback();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiGeneratedText = "哈囉！小時候家裡最常吃什麼呢？";
      });
      _triggerCurrentContextSequencePlayback();
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _processAudioAndChat({List<String>? audioPaths, String? manualText}) async {
    if (!mounted) return;
    setState(() { _isExtractingKeywords = true; });
    String userMessage = "";

    try {
      if (manualText != null && manualText.isNotEmpty) {
        userMessage = manualText;
        debugPrint("💬 [對話內容正式送交分析]: $userMessage");
      } else {
        if (_chatStatus == ChatStatus.completed) {
          userMessage = "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";
        } else if (_chatStatus == ChatStatus.dislikeCompleted) {
          userMessage = "這張不像啦，桌上只有一鍋蕃薯粥配醃蘿蔔而已。";
        } else {
          userMessage = "兄弟姊妹都會去山上摸魚。";
        }
      }

      final String reply = await _llmService.generateChatReply(userMessage, _chatHistory);
      final Map<String, dynamic> sceneData = await _llmService.extractSceneData(userMessage);

      final List<String> extracted = List<String>.from(sceneData['keywords'] ?? []);
      final String parsedScene = sceneData['scene']?.toString() ?? "台灣早期懷舊生活場景";
      final String parsedEra = sceneData['era']?.toString() ?? "1980s";
      final String parsedLocation = sceneData['location']?.toString() ?? "Taiwan";

      if (!mounted) return;
      setState(() {
        _aiGeneratedText = reply;

        if (_chatStatus == ChatStatus.completed || _chatStatus == ChatStatus.keywords) {
          _originalKeywords = extracted;
          _dynamicScene = parsedScene;
          _dynamicEra = parsedEra;
          _dynamicLocation = parsedLocation;
        } else {
          _newKeywords = extracted;
        }
      });

      _chatHistory.add({"role": "user", "content": userMessage});
      _chatHistory.add({"role": "assistant", "content": reply});

      _triggerCurrentContextSequencePlayback();

    } catch (e) {
      debugPrint("陪伴與智慧分析流發生錯誤: $e");
      if (!mounted) return;
      setState(() {
        _aiGeneratedText = "阿公阿嬤拍謝，我剛才不小心恍神了，可以再跟我說一次嗎？";
      });
      _triggerCurrentContextSequencePlayback();
    } finally {
      if (mounted) {
        setState(() { _isExtractingKeywords = false; });
      }
    }
  }

  Future<void> _triggerImageGeneration() async {
    if (!mounted) return;

    setState(() { _chatStatus = ChatStatus.generating; });
    await _stopAudioSequence();

    try {
      String prompt = _originalKeywords.join("、");
      if (prompt.isEmpty) prompt = "懷舊元素";

      final String? imageUrl = await _imageService.generateNostalgicImage(
        scene: "$_dynamicScene, 包含關鍵元素: $prompt",
        era: _dynamicEra,
        location: _dynamicLocation,
      );

      if (!mounted) return;
      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.evaluation;
        });
        _triggerCurrentContextSequencePlayback();
      } else {
        throw Exception("生圖出錯");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _chatStatus = ChatStatus.keywords; });
    }
  }

  Future<void> _triggerModifiedImageGeneration() async {
    if (!mounted) return;

    setState(() { _chatStatus = ChatStatus.dislikeGenerating; });
    await _stopAudioSequence();

    try {
      String combinedPrompt = _newKeywords.join("、");
      if (combinedPrompt.isEmpty) combinedPrompt = "修改後的食物與場景";

      final String? imageUrl = await _imageService.editImage(
        imagePath: _currentImageUrl,
        editInstruction: "在 $_dynamicScene 的大場景氛圍下, 將細節修改或新增為: $combinedPrompt",
      );

      if (!mounted) return;
      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.dislikeEvaluation;
        });
        _triggerCurrentContextSequencePlayback();
      } else {
        throw Exception("改圖出錯");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _chatStatus = ChatStatus.dislikeKeywords; });
    }
  }

  Future<void> _triggerLikeExtendedImageGeneration() async {
    if (!mounted) return;

    setState(() { _chatStatus = ChatStatus.likeGenerating; });
    await _stopAudioSequence();

    try {
      String combinedPrompt = [..._originalKeywords, ..._newKeywords].join("、");

      final String? imageUrl = await _imageService.generateNostalgicImage(
        scene: "$_dynamicScene, 包含關鍵元素: $combinedPrompt",
        era: _dynamicEra,
        location: _dynamicLocation,
      );

      if (!mounted) return;
      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.evaluation;
        });
        _triggerCurrentContextSequencePlayback();
      } else {
        throw Exception("延伸話題生圖出錯");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _chatStatus = ChatStatus.likeKeywords; });
    }
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = "";
    switch (_chatStatus) {
      case ChatStatus.prepare: appBarTitle = "準備聊天"; break;
      case ChatStatus.chatting:
      case ChatStatus.completed: appBarTitle = "點開始聊"; break;
      case ChatStatus.keywords: appBarTitle = "抓取關鍵詞"; break;
      case ChatStatus.generating:
      case ChatStatus.dislikeGenerating:
      case ChatStatus.likeGenerating: appBarTitle = "Ai 生圖中"; break;
      case ChatStatus.evaluation:
      case ChatStatus.dislikeEvaluation: appBarTitle = "問像不像"; break;
      case ChatStatus.dislikePrepare:
      case ChatStatus.dislikeChatting:
      case ChatStatus.dislikeCompleted:
      case ChatStatus.dislikeKeywords: appBarTitle = "不像，繼續聊天"; break;
      case ChatStatus.likePrepare:
      case ChatStatus.likeChatting:
      case ChatStatus.likeCompleted:
      case ChatStatus.likeKeywords: appBarTitle = "如果像，就 AI延伸話題"; break;
    }

    final bool showImageOnTop = _chatStatus == ChatStatus.evaluation ||
        _chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeChatting ||
        _chatStatus == ChatStatus.dislikeCompleted || _chatStatus == ChatStatus.dislikeKeywords ||
        _chatStatus == ChatStatus.dislikeEvaluation || _chatStatus == ChatStatus.likePrepare ||
        _chatStatus == ChatStatus.likeChatting || _chatStatus == ChatStatus.likeCompleted ||
        _chatStatus == ChatStatus.likeKeywords;

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

                          if (_chatStatus != ChatStatus.evaluation && _chatStatus != ChatStatus.dislikePrepare &&
                              _chatStatus != ChatStatus.dislikeChatting && _chatStatus != ChatStatus.likePrepare &&
                              _chatStatus != ChatStatus.likeChatting && _chatStatus != ChatStatus.dislikeEvaluation) ...[
                            LanguageSelector(
                              selectedLanguage: _selectedLanguage,
                              onLanguageSelected: _playCurrentContextVoice,
                            ),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus != ChatStatus.evaluation && _chatStatus != ChatStatus.dislikeEvaluation &&
                              _chatStatus != ChatStatus.dislikePrepare && _chatStatus != ChatStatus.dislikeChatting &&
                              _chatStatus != ChatStatus.likePrepare && _chatStatus != ChatStatus.likeChatting) ...[
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isLoading
                                  ? const QuestionLoadingIndicator()
                                  : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  QuestionArea(questionText: _aiGeneratedText),
                                  if (_chatStatus == ChatStatus.prepare) ...[
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await _stopAudioSequence();
                                        _fetchInitialQuestion();
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
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8)
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus == ChatStatus.keywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: const [],
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ] else if (_chatStatus == ChatStatus.dislikeKeywords || _chatStatus == ChatStatus.likeKeywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: _newKeywords,
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ],

                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _buildControlSection(),
                          ),

                          if (_isVoiceActiveStatus(_chatStatus))
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
  }

  Widget _buildVoiceAssistantIndicator() {
    bool isListeningNow = (_chatStatus == ChatStatus.chatting || _chatStatus == ChatStatus.dislikeChatting || _chatStatus == ChatStatus.likeChatting);
    bool isCompletedState = (_chatStatus == ChatStatus.completed || _chatStatus == ChatStatus.dislikeCompleted || _chatStatus == ChatStatus.likeCompleted);

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isListeningNow ? Colors.red[50] : Colors.green[50],
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isListeningNow ? Colors.red[200]! : Colors.green[200]!,
            width: 1,
          ),
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
                  ? "🎙️ 聆聽中... (講完停頓一下，AI 會自動接話)"
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
    return Container(
      width: 320,
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
      ),
      clipBehavior: Clip.antiAlias,
      child: _currentImageUrl.isNotEmpty
          ? (_currentImageUrl.startsWith('http') || _currentImageUrl.startsWith('https')
          ? Image.network(
        _currentImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.grey)));
        },
      )
          : (kIsWeb
          ? const Center(
        child: Text(
          'Web 瀏覽器無法讀取電腦硬碟檔案\n\n請改用 Windows 桌面版執行\n(或更新後端提供靜態網址)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      )
          : Image.file(
        File(_currentImageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
      )))
          : const Center(child: Icon(Icons.image, size: 64, color: Colors.grey)),
    );
  }

  Widget _buildControlSection() {
    switch (_chatStatus) {
      case ChatStatus.prepare:
        return PrepareView(
          onStartChat: _triggerStartChatFlow,
        );
      case ChatStatus.chatting:
        return ListeningView(
          recordSeconds: _recordSeconds,
          onEndRecording: _handleEndChat,
        );
      case ChatStatus.completed:
        return CompletedView(
          onRestartChat: _triggerStartChatFlow,
          onEndChat: () async {
            if (!mounted) return;
            await _stopAudioSequence();
            setState(() { _chatStatus = ChatStatus.keywords; });
            await _voiceManager.stopActiveAudioOperations();
          },
        );
      case ChatStatus.keywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerImageGeneration);
      case ChatStatus.generating:
        return const GeneratingView();
      case ChatStatus.evaluation:
        return EvaluationView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onLike: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.likePrepare; });
            _voiceManager.checkCompletedCommands = false;
            _voiceManager.startBackgroundWakeWordCycle();
            _triggerCurrentContextSequencePlayback();
          },
          onDislike: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.dislikePrepare; });
            _voiceManager.checkCompletedCommands = false;
            _voiceManager.startBackgroundWakeWordCycle();
            _triggerCurrentContextSequencePlayback();
          },
        );
      case ChatStatus.dislikePrepare:
        return DislikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: _triggerStartChatFlow,
        );
      case ChatStatus.dislikeChatting:
        return DislikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: _handleEndChat,
        );
      case ChatStatus.dislikeCompleted:
        return CompletedView(
          onRestartChat: _triggerStartChatFlow,
          onEndChat: () async {
            if (!mounted) return;
            await _stopAudioSequence();
            setState(() { _chatStatus = ChatStatus.dislikeKeywords; });
            await _voiceManager.stopActiveAudioOperations();
          },
        );
      case ChatStatus.dislikeKeywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerModifiedImageGeneration);
      case ChatStatus.dislikeGenerating:
        return const GeneratingView();
      case ChatStatus.dislikeEvaluation:
        return DislikeEvaluationView(
          onContinueModify: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.dislikePrepare; });
            _voiceManager.checkCompletedCommands = false;
            _voiceManager.startBackgroundWakeWordCycle();
            _triggerCurrentContextSequencePlayback();
          },
          onFinished: _resetAllStates,
        );
      case ChatStatus.likePrepare:
        return LikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: _triggerStartChatFlow,
        );
      case ChatStatus.likeChatting:
        return LikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: _handleEndChat,
        );
      case ChatStatus.likeCompleted:
        return CompletedView(
          onRestartChat: _triggerStartChatFlow,
          onEndChat: () async {
            if (!mounted) return;
            await _stopAudioSequence();
            setState(() { _chatStatus = ChatStatus.likeKeywords; });
            await _voiceManager.stopActiveAudioOperations();
          },
        );
      case ChatStatus.likeKeywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerLikeExtendedImageGeneration);
      case ChatStatus.likeGenerating:
        return const GeneratingView();
    }
  }
}