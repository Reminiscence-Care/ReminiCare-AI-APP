import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

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
import '../../../services/audio_services/stt_result.dart';
import '../../../services/topic_catalog.dart';

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
       _injectedStt = sttService;

  final ReminiscenceAiService? _injectedAi;
  final IImageGenerationClient? _injectedImage;
  final ISTTService? _injectedStt;

  late ReminiscenceAiService _ai;
  late IImageGenerationClient _image;
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
  bool isTranscribing = false;
  int transcriptionComplete = 0;
  int transcriptionTotal = 0;
  List<String> _pendingAudio = [];
  bool get canRetryTranscription => _pendingAudio.isNotEmpty && !isTranscribing;
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
    _stt = _injectedStt ?? ApiServices().stt;
    await _cleanupStaleRecordings();
    await refreshTopics();
  }

  Future<void> refreshTopics() async {
    final previousIds = topics.map((topic) => topic.topicId).toSet();
    final requestSession = ++_session;
    stage = LifeStage.topicLoading;
    topics = const [];
    selectedTopic = null;
    errorMessage = null;
    topicWarning = null;
    imageWarning = null;
    _notify();
    final catalog = await TopicCatalog.load();
    if (!_isCurrent(requestSession)) return;
    topics = catalog.pickFour(excluding: previousIds);
    stage = LifeStage.topicSelection;
    _notify();
    final originalTopics = topics;
    try {
      final enriched = await _ai.questionsForTopics(originalTopics);
      if (!_isCurrent(requestSession) || stage != LifeStage.topicSelection) {
        return;
      }
      topics = enriched;
    } catch (_) {
      if (!_isCurrent(requestSession)) return;
      topicWarning = '暫時使用預設問題。';
    }
    _notify();
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
    if (await _startRecording()) {
      introductionState = IntroductionState.recording;
    }
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
    _session++;
    await _stopAllAudio();
    await _clearPendingAudio();
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
      if (selectedTopic?.topicId != null) 'topicId': selectedTopic!.topicId,
    };
    final history = prefs.getStringList('chat_memories') ?? [];
    await prefs.setStringList('chat_memories', [...history, jsonEncode(data)]);
  }

  Future<void> leave() async {
    _session++;
    await _stopAllAudio();
    await _clearPendingAudio();
  }

  Future<bool> _startRecording() async {
    if (_busy || isTranscribing || isRecording) return false;
    _busy = true;
    try {
      await _clearPendingAudio();
      errorMessage = null;
      final voice = _ensureVoice();
      await voice.stopCurrentPlayback();
      await voice.stopActiveAudioOperations();
      final key = stage == LifeStage.introduction
          ? 'VOICE_INTRO_SILENCE_SECONDS'
          : 'VOICE_CHAT_SILENCE_SECONDS';
      final seconds =
          double.tryParse(ReminiCareConfig.getValue(key)) ??
          (stage == LifeStage.introduction ? 3 : 6);
      await voice.startChatFlow(
        silenceTimeout: Duration(milliseconds: (seconds * 1000).round()),
      );
      if (_disposed) return false;
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
      return true;
    } catch (error) {
      isRecording = false;
      errorMessage = error is SttException ? error.message : '無法啟動麥克風，請重試。';
      _notify();
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<void> completeRecording(List<String> paths) async {
    if (_disposed || _busy) return;
    isRecording = false;
    _recordTimer?.cancel();
    _pendingAudio = paths;
    if (paths.isEmpty) {
      errorMessage = '錄音未成功儲存，請重新錄音。';
      introductionState = IntroductionState.ready;
      _notify();
      return;
    }
    await retryTranscription();
  }

  Future<void> retryTranscription() async {
    if (_disposed || _busy || _pendingAudio.isEmpty) return;
    _busy = true;
    isTranscribing = true;
    errorMessage = null;
    if (stage == LifeStage.introduction) {
      introductionState = IntroductionState.processing;
    }
    _notify();
    final requestSession = _session;
    try {
      final paths = [..._pendingAudio];
      final text = await _transcribe(paths);
      if (!_isCurrent(requestSession)) return;
      await _clearPendingAudio();
      if (text.trim().isEmpty) {
        errorMessage = '沒有辨識到語音，請重新錄音。';
        if (stage == LifeStage.introduction) {
          introductionState = IntroductionState.ready;
        }
        return;
      }

      if (stage == LifeStage.introduction) {
        introductionState = IntroductionState.processing;
        _notify();
        try {
          final name = await _ai.extractElderName(text);
          if (!_isCurrent(requestSession)) return;
          currentElderName = name;
        } catch (_) {
          if (!_isCurrent(requestSession)) return;
          currentElderName = '';
          errorMessage = '沒有確認到您的姓名，請再介紹一次，並說明希望怎麼稱呼您。';
          introductionState = IntroductionState.ready;
          return;
        }
        if (!_isCurrent(requestSession)) return;
        introductionState = IntroductionState.confirmed;
        _notify();
        return;
      }

      transcript = text;
      if (stage == LifeStage.revisionRecording) {
        await _reviseImage(requestSession, text);
      } else {
        await _createMemoryImage(requestSession, text);
      }
    } catch (error) {
      if (!_isCurrent(requestSession)) return;
      errorMessage = error is SttException ? error.message : '語音辨識失敗，請重試或重新錄音。';
      if (stage == LifeStage.introduction) {
        introductionState = IntroductionState.ready;
      }
    } finally {
      _busy = false;
      isTranscribing = false;
      _notify();
    }
  }

  Future<String> _transcribe(List<String> paths) async {
    final requestSession = _session;
    final parts = <String>[];
    for (final path in paths) {
      if (_stt is ProgressSttService) {
        (_stt as ProgressSttService).onProgress = (complete, total) {
          if (!_isCurrent(requestSession)) return;
          transcriptionComplete = complete;
          transcriptionTotal = total;
          _notify();
        };
      }
      final result = await _stt.transcribeResult(path);
      if (result.error != null) throw result.error!;
      if (!result.isSilent) parts.add(result.text.trim());
    }
    return parts.join('，');
  }

  Future<void> _clearPendingAudio() async {
    final paths = _pendingAudio;
    _pendingAudio = [];
    if (paths.isNotEmpty && _stt is ProgressSttService) {
      (_stt as ProgressSttService).onProgress = null;
    }
    for (final path in paths) {
      if (_stt is ProgressSttService) (_stt as ProgressSttService).forget(path);
      if (!kIsWeb) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _cleanupStaleRecordings() async {
    if (kIsWeb) return;
    try {
      final root = await getTemporaryDirectory();
      final deadline = DateTime.now().subtract(const Duration(hours: 24));
      await for (final entry in root.list()) {
        if (entry is File &&
            entry.uri.pathSegments.last.startsWith('reminicare_chat_smart_') &&
            (await entry.stat()).modified.isBefore(deadline)) {
          await entry.delete();
        }
      }
    } catch (_) {
      /* An unavailable temporary directory must not block startup. */
    }
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
      if (!_isCurrent(requestSession)) return;
      final imagePath = await _image.generate(prompt: prompt);
      if (!_isCurrent(requestSession)) return;
      currentImagePath = imagePath;
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
      String imagePath;
      if (canEditImage) {
        imagePath = await _image.edit(
          imagePath: currentImagePath,
          instruction: instruction.trim().isEmpty
              ? 'Make the image better match the speaker’s memory while preserving the people and composition.'
              : instruction,
        );
      } else {
        final prompt = const NostalgicImagePromptBuilder().build(
          scene:
              '${selectedTopic?.imagePrompt ?? ''}. Requested correction: $instruction',
        );
        imagePath = await _image.generate(prompt: prompt);
      }
      if (!_isCurrent(requestSession)) return;
      currentImagePath = imagePath;
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
      ..onSpeechCompleted = (paths) => unawaited(completeRecording(paths));
    _voice = manager;
    return manager;
  }

  Future<void> _stopAllAudio() async {
    _recordTimer?.cancel();
    isRecording = false;
    await _voice?.stopCurrentPlayback();
    await _voice?.stopActiveAudioOperations();
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
    unawaited(_clearPendingAudio());
    super.dispose();
  }
}
