import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/reminiscence_topic.dart';
import '../../../services/ai/ai_models.dart';
import '../../../services/ai/ai_service_exception.dart';
import '../../../services/ai/reminiscence_ai_service.dart';
import '../../../services/api_services.dart';
import '../../../services/audio_services/speech_services.dart';
import '../../../services/audio_services/voice_assistant_services.dart';
import '../../../services/image_gen_api_service.dart';
import '../../../services/remini_care_config.dart';
import '../../../services/topic_image_search_service.dart';

enum LifeStage {
  topicLoading,
  topicSelection,
  introduction,
  question,
  imageGenerating,
  evaluation,
  revisionRecording,
  revisionGenerating,
  summary,
}

enum IntroductionState { ready, recording, processing, confirmed }

class LifeScreenController extends ChangeNotifier {
  LifeScreenController({
    ReminiscenceAiService? aiService,
    IImageGenerationClient? imageService,
    ITopicImageSearchClient? topicImageSearchService,
    ISTTService? sttService,
  }) : _injectedAi = aiService,
       _injectedImage = imageService,
       _injectedTopicImages = topicImageSearchService,
       _injectedStt = sttService;

  final ReminiscenceAiService? _injectedAi;
  final IImageGenerationClient? _injectedImage;
  final ITopicImageSearchClient? _injectedTopicImages;
  final ISTTService? _injectedStt;

  late ReminiscenceAiService _ai;
  late IImageGenerationClient _image;
  late ITopicImageSearchClient _topicImages;
  late ISTTService _stt;
  VoiceAssistantManager? _voice;

  LifeStage stage = LifeStage.topicLoading;
  IntroductionState introductionState = IntroductionState.ready;
  List<ReminiscenceTopic> topics = const [];
  ReminiscenceTopic? selectedTopic;
  List<String> elderNames = [];
  String currentElderName = '';
  String selectedLanguage = '台語';
  String currentQuestion = '';
  String transcript = '';
  List<String> keywords = [];
  String currentImagePath = '';
  String? errorMessage;
  String? topicWarning;
  String? imageWarning;
  int recordSeconds = 0;
  bool isRecording = false;
  bool hasExtension = false;

  int _session = 0;
  bool _disposed = false;
  bool _busy = false;
  Timer? _recordTimer;

  bool get canEditImage =>
      _image.config.supports(ProviderCapability.imageEditing);

  Future<void> initialize() async {
    await ReminiCareConfig.loadConfig();
    if (_disposed) return;
    _ai = _injectedAi ?? ApiServices().reminiscenceAi;
    _image = _injectedImage ?? ApiServices().image;
    _topicImages =
        _injectedTopicImages ??
        WikimediaTopicImageSearchClient();
    _stt = _injectedStt ?? ApiServices().stt;
    await refreshTopics();
  }

  Future<void> refreshTopics() async {
    final requestSession = ++_session;
    stage = LifeStage.topicLoading;
    topics = const [];
    selectedTopic = null;
    errorMessage = null;
    topicWarning = null;
    imageWarning = null;
    _notify();
    final result = await _ai.recommendTopicsWithStatus();
    if (!_isCurrent(requestSession)) return;
    topics = result.topics;
    topicWarning = result.warning;
    if (result.usedFallback) {
      debugPrint('[主題推薦] LLM 失敗，改用本地題庫：${result.warning}');
    }
    stage = LifeStage.topicSelection;
    _notify();
    await _searchTopicThumbnails(requestSession);
  }

  Future<void> _searchTopicThumbnails(int requestSession) async {
    final totalTimer = Stopwatch()..start();
    var next = 0;
    final usedSourceIds = <String>{};
    Future<void> worker() async {
      while (_isCurrent(requestSession)) {
        final index = next++;
        if (index >= topics.length) return;
        final topic = topics[index];
        _replaceTopic(
          index,
          topic.copyWith(
            thumbnailPath: null,
            thumbnailSourceId: null,
            thumbnailAttribution: null,
            thumbnailStatus: ThumbnailStatus.loading,
          ),
        );
        try {
          final imageTimer = Stopwatch()..start();
          var result = await _topicImages.findForTopic(
            topic,
            excludedSourceIds: {...usedSourceIds},
          );
          if (!_isCurrent(requestSession)) return;
          if (!usedSourceIds.add(result.sourceId)) {
            result = await _topicImages.findForTopic(
              topic,
              excludedSourceIds: {...usedSourceIds},
            );
            if (!_isCurrent(requestSession)) return;
            if (!usedSourceIds.add(result.sourceId)) {
              throw const TopicImageSearchException('搜尋結果與其他主題重複。');
            }
          }
          _replaceTopic(
            index,
            topics[index].copyWith(
              thumbnailPath: result.path,
              thumbnailSourceId: result.sourceId,
              thumbnailWidth: result.width,
              thumbnailHeight: result.height,
              thumbnailAttribution: result.attribution,
              thumbnailStatus: ThumbnailStatus.ready,
            ),
          );
          imageTimer.stop();
          debugPrint(
            '[主題圖片]「${topic.title}」完成：${imageTimer.elapsedMilliseconds} ms',
          );
        } catch (error) {
          if (!_isCurrent(requestSession)) return;
          imageWarning ??= error is AiServiceException
              ? '雲端圖片判斷未成功：${error.message}'
              : '部分主題圖片未找到，仍可直接選擇主題。';
          debugPrint('[主題縮圖] 第 ${index + 1} 張搜尋失敗：$error');
          _replaceTopic(
            index,
            topics[index].copyWith(thumbnailStatus: ThumbnailStatus.failed),
          );
        }
      }
    }

    await Future.wait([worker(), worker()]);
    totalTimer.stop();
    debugPrint('[主題圖片] 四張處理完成：${totalTimer.elapsedMilliseconds} ms');
  }

  void selectTopic(ReminiscenceTopic topic) {
    if (stage != LifeStage.topicSelection) return;
    _session++;
    selectedTopic = topic;
    currentQuestion = topic.question;
    stage = LifeStage.introduction;
    introductionState = IntroductionState.ready;
    _notify();
    unawaited(_play('請大家介紹自己'));
  }

  Future<void> startIntroductionRecording() async {
    if (_busy || introductionState == IntroductionState.recording) return;
    await _startRecording();
    introductionState = IntroductionState.recording;
    _notify();
  }

  Future<void> stopIntroductionRecording() =>
      _voice?.forceEndChat() ?? Future.value();

  void addNextParticipant() {
    if (currentElderName.isNotEmpty && currentElderName != '長輩') {
      elderNames.add(currentElderName);
    }
    currentElderName = '';
    introductionState = IntroductionState.ready;
    _notify();
  }

  Future<void> finishIntroduction() async {
    if (currentElderName.isNotEmpty && currentElderName != '長輩') {
      elderNames.add(currentElderName);
    }
    currentElderName = '';
    stage = LifeStage.question;
    introductionState = IntroductionState.ready;
    _notify();
    await _play(currentQuestion, bothLanguages: true);
  }

  Future<void> startAnswerRecording() async {
    if (_busy || stage != LifeStage.question) return;
    transcript = '';
    await _startRecording();
    _notify();
  }

  Future<void> stopAnswerRecording() =>
      _voice?.forceEndChat() ?? Future.value();

  Future<void> chooseLike() async {
    if (_busy || stage != LifeStage.evaluation) return;
    if (hasExtension) {
      await finishSession();
      return;
    }
    _busy = true;
    errorMessage = null;
    try {
      currentQuestion = await _ai.generateExtendedQuestion(
        currentQuestion,
        transcript,
      );
    } catch (_) {
      currentQuestion = selectedTopic?.followUpQuestion ?? '這張照片還讓您想到什麼往事？';
    }
    hasExtension = true;
    _busy = false;
    stage = LifeStage.question;
    _notify();
    await _play(currentQuestion, bothLanguages: true);
  }

  void chooseDislike() {
    if (stage != LifeStage.evaluation) return;
    stage = LifeStage.revisionRecording;
    _notify();
    unawaited(_play('哪裡不太像呢？請告訴我想修改的地方。'));
  }

  Future<void> startRevisionRecording() async {
    if (_busy || stage != LifeStage.revisionRecording) return;
    transcript = '';
    await _startRecording();
    _notify();
  }

  Future<void> finishSession() async {
    await _stopAllAudio();
    stage = LifeStage.summary;
    _notify();
  }

  Future<void> replayLanguage(String language) async {
    selectedLanguage = language;
    _notify();
    await _play(_spokenText, language: language);
  }

  Future<void> saveMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final data = <String, dynamic>{
      'date':
          '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}',
      'topic': selectedTopic?.title ?? '懷舊時光',
      'content': keywords.isEmpty ? transcript : keywords.join('、'),
      'elders': elderNames.isEmpty ? '未留名' : elderNames.join('、'),
      'imagePath': currentImagePath,
    };
    final history = prefs.getStringList('chat_memories') ?? [];
    await prefs.setStringList('chat_memories', [...history, jsonEncode(data)]);
  }

  Future<void> leave() async {
    _session++;
    await _stopAllAudio();
  }

  Future<void> _startRecording() async {
    final voice = _ensureVoice();
    await voice.stopCurrentPlayback();
    await voice.stopActiveAudioOperations();
    isRecording = true;
    recordSeconds = 0;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed || !isRecording) return timer.cancel();
      recordSeconds++;
      _notify();
      if (recordSeconds >=
          (int.tryParse(ReminiCareConfig.maxRecordLimit) ?? 180)) {
        unawaited(voice.forceEndChat());
      }
    });
    await voice.startChatFlow();
  }

  Future<void> _onSpeechCompleted(List<String> paths) async {
    if (_disposed || _busy) return;
    isRecording = false;
    _recordTimer?.cancel();
    _busy = true;
    final requestSession = _session;
    final text = await _transcribe(paths);
    if (!_isCurrent(requestSession)) return;

    if (stage == LifeStage.introduction) {
      introductionState = IntroductionState.processing;
      _notify();
      try {
        currentElderName = text.isEmpty
            ? '長輩'
            : await _ai.extractElderName(text);
      } catch (_) {
        currentElderName = '長輩';
      }
      if (!_isCurrent(requestSession)) return;
      introductionState = IntroductionState.confirmed;
      _busy = false;
      _notify();
      return;
    }

    transcript = text;
    if (stage == LifeStage.revisionRecording) {
      await _reviseImage(requestSession, text);
    } else {
      await _createMemoryImage(requestSession, text);
    }
    _busy = false;
  }

  Future<String> _transcribe(List<String> paths) async {
    final parts = <String>[];
    for (final path in paths) {
      try {
        final value = await _stt.transcribe(path);
        if (value != null && value.trim().isNotEmpty) parts.add(value.trim());
      } finally {
        if (!kIsWeb) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      }
    }
    return parts.join('，');
  }

  Future<void> _createMemoryImage(int requestSession, String text) async {
    stage = LifeStage.imageGenerating;
    errorMessage = null;
    _notify();
    var scene = selectedTopic?.imagePrompt ?? text;
    try {
      final data = await _ai.extractSceneData(text);
      keywords = (data['keywords'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      scene = data['scene']?.toString() ?? scene;
    } catch (_) {
      keywords = text
          .split(RegExp(r'[，。\s]+'))
          .where((e) => e.length >= 2)
          .take(5)
          .toList();
    }
    try {
      final prompt = const NostalgicImagePromptBuilder().build(scene: scene);
      currentImagePath = await _image.generate(prompt: prompt);
      if (!_isCurrent(requestSession)) return;
      stage = LifeStage.evaluation;
    } on AiServiceException catch (error) {
      if (!_isCurrent(requestSession)) return;
      errorMessage = error.message;
      stage = LifeStage.question;
    }
    _notify();
    if (stage == LifeStage.evaluation) {
      await _play('這張照片像您的回憶嗎？', bothLanguages: true);
    }
  }

  Future<void> _reviseImage(int requestSession, String instruction) async {
    stage = LifeStage.revisionGenerating;
    errorMessage = null;
    _notify();
    try {
      if (canEditImage) {
        currentImagePath = await _image.edit(
          imagePath: currentImagePath,
          instruction: instruction,
        );
      } else {
        final prompt = const NostalgicImagePromptBuilder().build(
          scene:
              '${selectedTopic?.imagePrompt ?? ''}. Requested correction: $instruction',
        );
        currentImagePath = await _image.generate(prompt: prompt);
      }
      if (!_isCurrent(requestSession)) return;
      stage = LifeStage.evaluation;
    } on AiServiceException catch (error) {
      if (!_isCurrent(requestSession)) return;
      errorMessage = error.message;
      stage = LifeStage.revisionRecording;
    }
    _busy = false;
    _notify();
    if (stage == LifeStage.evaluation) {
      await _play('這樣像嗎？', bothLanguages: true);
    }
  }

  String get _spokenText => switch (stage) {
    LifeStage.introduction => '請大家介紹自己',
    LifeStage.question => currentQuestion,
    LifeStage.evaluation => hasExtension ? '這樣像嗎？' : '這張照片像您的回憶嗎？',
    LifeStage.revisionRecording => '哪裡不太像呢？請告訴我想修改的地方。',
    _ => currentQuestion,
  };

  Future<void> _play(
    String text, {
    String? language,
    bool bothLanguages = false,
  }) async {
    if (text.isEmpty || _disposed) return;
    await _ensureVoice().playLanguageSequence(
      texts: [text],
      languages: bothLanguages
          ? const ['台語', '中文']
          : [language ?? selectedLanguage],
    );
  }

  VoiceAssistantManager _ensureVoice() {
    final existing = _voice;
    if (existing != null) return existing;
    final manager = VoiceAssistantManager()
      ..onPlayingLanguageChanged = (language) {
        if (_disposed) return;
        selectedLanguage = language;
        _notify();
      }
      ..onSpeechCompleted = (paths) => unawaited(_onSpeechCompleted(paths));
    _voice = manager;
    return manager;
  }

  Future<void> _stopAllAudio() async {
    _recordTimer?.cancel();
    isRecording = false;
    await _voice?.stopCurrentPlayback();
    await _voice?.stopActiveAudioOperations();
  }

  void _replaceTopic(int index, ReminiscenceTopic topic) {
    topics = [...topics]..[index] = topic;
    _notify();
  }

  bool _isCurrent(int value) => !_disposed && value == _session;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _recordTimer?.cancel();
    _voice?.dispose();
    super.dispose();
  }
}
