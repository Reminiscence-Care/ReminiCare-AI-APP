import '../../../services/app_log.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/reminiscence_topic.dart';
import '../../../models/participant_address.dart';
import '../../../models/conversation_turn.dart';
import '../../../services/memory_repository.dart';
import '../../../services/audio_services/speech_recognition_job.dart';
import '../../../services/audio_services/audio_ports.dart';
import '../../../services/ai/ai_http_transport.dart';
import '../../../services/ai/ai_models.dart';
import '../../../services/ai/ai_service_exception.dart';
import '../../../services/ai/reminiscence_ai_service.dart';
import '../../../services/api_services.dart';
import '../../../services/audio_services/speech_services.dart';
import '../../../services/audio_services/voice_assistant_services.dart';
import '../../../services/image_gen_api_service.dart';
import '../../../services/remini_care_config.dart';
import '../../../services/audio_services/stt_result.dart';
import '../../../services/topic_catalog.dart';
import '../../../services/debug_flow.dart';

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
    ISTTService? sttService,
    VoiceAssistantManager Function()? voiceFactory,
    MemoryRepository? memoryRepository,
    bool? debugFixedFlow,
    DebugAudioSource? debugAudioSource,
  }) : _injectedAi = aiService,
       _injectedImage = imageService,
       _injectedStt = sttService,
       _voiceFactory = voiceFactory,
       _debugOverride = debugFixedFlow,
       _debugAudioSource = debugAudioSource,
       _memories = memoryRepository ?? MemoryRepository();
  final bool? _debugOverride;
  final DebugAudioSource? _debugAudioSource;
  bool _debugFixedFlow = false;
  bool _debugModeLocked = false;
  bool get debugFixedFlow => _debugFixedFlow;
  final VoiceAssistantManager Function()? _voiceFactory;
  final MemoryRepository _memories;
  String? _memoryId;
  bool _saving = false;
  bool _saved = false;
  bool get isSaving => _saving;
  bool get isSaved => _saved;
  final List<ConversationTurn> _turns = [];
  List<ConversationTurn> get turns => List.unmodifiable(_turns);
  final Set<String> _sessionImages = {};
  String? _audioWarning;
  String? get audioWarning => _audioWarning;
  bool get hasInterruptedRecording => _interrupted;
  bool _interrupted = false;
  SpeechRecognitionJob? _activeJob;
  StreamSubscription<SpeechProgress>? _jobProgress;
  String _lastText = '';
  bool _lastWasRevision = false;
  bool get canRetryLastStep =>
      !_busy &&
      _lastText.isNotEmpty &&
      _errorMessage != null &&
      {
        LifeStage.introduction,
        LifeStage.question,
        LifeStage.revisionRecording,
      }.contains(_stage);
  String get memoryTranscript => _turns
      .where((turn) => turn.kind == ConversationTurnKind.memory)
      .map((turn) => turn.text)
      .join('，');

  final ReminiscenceAiService? _injectedAi;
  final IImageGenerationClient? _injectedImage;
  final ISTTService? _injectedStt;

  late ReminiscenceAiService _ai;
  late IImageGenerationClient _image;
  late ISTTService _stt;
  VoiceAssistantManager? _voice;

  LifeStage _stage = LifeStage.topicLoading;
  LifeStage get stage => _stage;
  IntroductionState _introductionState = IntroductionState.ready;
  IntroductionState get introductionState => _introductionState;
  List<ReminiscenceTopic> _topics = const [];
  List<ReminiscenceTopic> get topics => List.unmodifiable(_topics);
  ReminiscenceTopic? _selectedTopic;
  ReminiscenceTopic? get selectedTopic => _selectedTopic;
  List<String> _elderNames = [];
  List<String> get elderNames => List.unmodifiable(_elderNames);
  String _currentElderName = '';
  String get currentElderName => _currentElderName;
  int _introductionRevision = 0;
  int get introductionRevision => _introductionRevision;
  String _selectedLanguage = '台語';
  String get selectedLanguage => _selectedLanguage;
  String _currentQuestion = '';
  String get currentQuestion => _currentQuestion;
  String _transcript = '';
  String get transcript => _transcript;
  List<String> _keywords = [];
  List<String> get keywords => List.unmodifiable(_keywords);
  String _currentImagePath = '';
  String get currentImagePath => _currentImagePath;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  String? _topicWarning;
  String? get topicWarning => _topicWarning;
  String? _imageWarning;
  String? get imageWarning => _imageWarning;
  int _recordSeconds = 0;
  int get recordSeconds => _recordSeconds;
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  bool _isTranscribing = false;
  bool get isTranscribing => _isTranscribing;
  int _transcriptionComplete = 0;
  int get transcriptionComplete => _transcriptionComplete;
  int _transcriptionTotal = 0;
  int get transcriptionTotal => _transcriptionTotal;
  List<String> _pendingAudio = [];
  bool get canRetryTranscription =>
      _pendingAudio.isNotEmpty && !_isTranscribing;
  bool _hasExtension = false;
  bool get hasExtension => _hasExtension;

  int _session = 0;
  bool _disposed = false;
  bool _closed = false;
  bool _servicesReady = false;
  bool _busy = false;
  Timer? _recordTimer;

  bool get canEditImage =>
      _image.config.supports(ProviderCapability.imageEditing);

  /// Test fixtures seed state without exposing writable production properties.
  @visibleForTesting
  void restoreForTesting({
    LifeStage? stage,
    IntroductionState? introductionState,
    List<ReminiscenceTopic>? topics,
    ReminiscenceTopic? selectedTopic,
    List<String>? elderNames,
    String? currentElderName,
    String? selectedLanguage,
    String? currentQuestion,
    String? transcript,
    List<String>? keywords,
    String? currentImagePath,
    String? errorMessage,
    String? topicWarning,
    String? imageWarning,
    int? recordSeconds,
    bool? isRecording,
    bool? isTranscribing,
    int? transcriptionComplete,
    int? transcriptionTotal,
    bool? hasExtension,
    String? audioWarning,
  }) {
    if (stage != null) _stage = stage;
    if (introductionState != null) _introductionState = introductionState;
    if (topics != null) _topics = topics;
    if (selectedTopic != null) _selectedTopic = selectedTopic;
    if (elderNames != null) _elderNames = elderNames;
    if (currentElderName != null) _currentElderName = currentElderName;
    if (selectedLanguage != null) _selectedLanguage = selectedLanguage;
    if (currentQuestion != null) _currentQuestion = currentQuestion;
    if (transcript != null) _transcript = transcript;
    if (keywords != null) _keywords = keywords;
    if (currentImagePath != null) _currentImagePath = currentImagePath;
    if (errorMessage != null) _errorMessage = errorMessage;
    if (topicWarning != null) _topicWarning = topicWarning;
    if (imageWarning != null) _imageWarning = imageWarning;
    if (recordSeconds != null) _recordSeconds = recordSeconds;
    if (isRecording != null) _isRecording = isRecording;
    if (isTranscribing != null) _isTranscribing = isTranscribing;
    if (transcriptionComplete != null) {
      _transcriptionComplete = transcriptionComplete;
    }
    if (transcriptionTotal != null) _transcriptionTotal = transcriptionTotal;
    if (hasExtension != null) _hasExtension = hasExtension;
    if (audioWarning != null) _audioWarning = audioWarning;
  }

  Future<void> initialize() async {
    _errorMessage = null;
    try {
      await ReminiCareConfig.loadConfig();
      if (_disposed || _closed) return;
      if (!_debugModeLocked) {
        _debugFixedFlow = ReminiCareConfig.resolveDebugFixedFlow(
          _debugOverride,
        );
        _debugModeLocked = true;
      }
      _ai = _injectedAi ?? ApiServices().reminiscenceAi;
      _image = _injectedImage ?? ApiServices().image;
      _stt = _injectedStt ?? ApiServices().stt;
      _servicesReady = true;
      await _cleanupStaleRecordings();
      await refreshTopics();
    } catch (_) {
      if (!_disposed && !_closed) {
        _stage = LifeStage.topicLoading;
        _errorMessage = '初始化失敗，請重試。';
        _notify();
      }
    }
  }

  Future<void> refreshTopics() async {
    final previousIds = _topics.map((topic) => topic.topicId).toSet();
    final requestSession = ++_session;
    _stage = LifeStage.topicLoading;
    _topics = const [];
    _selectedTopic = null;
    _errorMessage = null;
    _topicWarning = null;
    _imageWarning = null;
    _notify();
    final catalog = await TopicCatalog.load();
    if (!_isCurrent(requestSession)) return;
    _topics = _debugFixedFlow
        ? DebugFlow.topics(catalog)
        : catalog.pickFour(excluding: previousIds);
    _stage = LifeStage.topicSelection;
    _notify();
    if (_debugFixedFlow) return;
    final originalTopics = _topics;
    try {
      final enriched = await _ai.questionsForTopics(originalTopics);
      if (!_isCurrent(requestSession) || _stage != LifeStage.topicSelection) {
        return;
      }
      _topics = enriched;
    } catch (_) {
      if (!_isCurrent(requestSession)) return;
      _topicWarning = '暫時使用預設問題。';
    }
    _notify();
  }

  void selectTopic(ReminiscenceTopic topic) {
    if (_stage != LifeStage.topicSelection) return;
    _introductionRevision++;
    _session++;
    _cancelAi();
    _selectedTopic = topic;
    _currentQuestion = topic.question;
    _stage = LifeStage.introduction;
    _introductionState = IntroductionState.ready;
    _notify();
    unawaited(_play('請大家介紹自己', bothLanguages: true));
  }

  Future<void> startIntroductionRecording() async {
    if (_disposed ||
        _closed ||
        _stage != LifeStage.introduction ||
        _busy ||
        _introductionState == IntroductionState.recording) {
      return;
    }
    if (_debugFixedFlow && _debugAudioSource != null) {
      _introductionRevision++;
      await _submitDebugAudio(DebugAudioSlot.introduction);
      return;
    }
    _introductionRevision++;
    if (await _startRecording()) {
      _introductionState = IntroductionState.recording;
    }
    _notify();
  }

  Future<void> stopIntroductionRecording() =>
      _voice?.forceEndChat() ?? Future.value();

  void addNextParticipant() {
    if (_disposed ||
        _busy ||
        _introductionState != IntroductionState.confirmed ||
        _stage != LifeStage.introduction) {
      return;
    }
    _introductionRevision++;
    if (_currentElderName.isNotEmpty && _currentElderName != '長輩') {
      _elderNames.add(_currentElderName);
    }
    _currentElderName = '';
    _introductionState = IntroductionState.ready;
    _notify();
  }

  Future<void> finishIntroduction() async {
    if (_disposed ||
        _busy ||
        _introductionState != IntroductionState.confirmed ||
        _stage != LifeStage.introduction) {
      return;
    }
    _introductionRevision++;
    if (_currentElderName.isNotEmpty && _currentElderName != '長輩') {
      _elderNames.add(_currentElderName);
    }
    _currentElderName = '';
    _stage = LifeStage.question;
    _introductionState = IntroductionState.ready;
    _notify();
    await _play(_currentQuestion, bothLanguages: true);
  }

  void correctParticipantAddress(
    ParticipantAddress address, {
    required int revision,
  }) {
    if (_disposed ||
        _busy ||
        _isRecording ||
        (_introductionState != IntroductionState.ready &&
            _introductionState != IntroductionState.confirmed) ||
        _stage != LifeStage.introduction ||
        revision != _introductionRevision ||
        !address.isValid) {
      return;
    }
    _currentElderName = address.displayName;
    _introductionState = IntroductionState.confirmed;
    _errorMessage = null;
    _introductionRevision++;
    _notify();
  }

  Future<void> startAnswerRecording() async {
    if (_busy || _stage != LifeStage.question) return;
    _transcript = '';
    if (_debugFixedFlow && _debugAudioSource != null) {
      await _submitDebugAudio(
        _hasExtension ? DebugAudioSlot.extension : DebugAudioSlot.answer,
      );
      return;
    }
    await _startRecording();
    _notify();
  }

  Future<void> stopAnswerRecording() =>
      _voice?.forceEndChat() ?? Future.value();

  Future<void> chooseLike() async {
    if (_busy || _stage != LifeStage.evaluation) return;
    if (_hasExtension) {
      await finishSession();
      return;
    }
    _busy = true;
    final requestSession = _session;
    _errorMessage = null;
    try {
      final question = _debugFixedFlow
          ? _selectedTopic!.followUpQuestion
          : await _ai.generateExtendedQuestion(
              _currentQuestion,
              memoryTranscript,
            );
      if (!_isCurrent(requestSession)) return;
      _currentQuestion = question;
    } catch (_) {
      if (!_isCurrent(requestSession)) return;
      _currentQuestion = _selectedTopic?.followUpQuestion ?? '這張照片還讓您想到什麼往事？';
    }
    _hasExtension = true;
    _busy = false;
    _stage = LifeStage.question;
    _notify();
    await _play(_currentQuestion, bothLanguages: true);
  }

  void chooseDislike() {
    if (_busy || _closed || _stage != LifeStage.evaluation) return;
    _stage = LifeStage.revisionRecording;
    _notify();
    unawaited(_play('哪裡不太像呢？請告訴我想修改的地方。'));
  }

  Future<void> startRevisionRecording() async {
    if (_busy || _stage != LifeStage.revisionRecording) return;
    _transcript = '';
    if (_debugFixedFlow && _debugAudioSource != null) {
      await _submitDebugAudio(DebugAudioSlot.revision);
      return;
    }
    await _startRecording();
    _notify();
  }

  Future<void> finishSession() async {
    final requestSession = ++_session;
    _cancelAi();
    _activeJob?.cancel();
    _busy = true;
    _isTranscribing = false;
    await _stopAllAudio();
    await _clearPendingAudio();
    if (!_isCurrent(requestSession)) return;
    _busy = false;
    _stage = LifeStage.summary;
    _notify();
  }

  Future<void> replayLanguage(String language) async {
    _selectedLanguage = language;
    _notify();
    await _play(_spokenText, language: language);
  }

  Future<bool> saveMemory() async {
    if (_saving || _saved || _disposed || _stage != LifeStage.summary) {
      return _saved;
    }
    final saveWatch = Stopwatch()..start();
    AppLog.instance.record(LogArea.history, LogEvent.saving);
    _saving = true;
    _errorMessage = null;
    _notify();
    try {
      final now = DateTime.now();
      final data = <String, dynamic>{
        'date':
            '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}',
        'topic': _selectedTopic?.title ?? '懷舊時光',
        'content': memoryTranscript.isEmpty ? _transcript : memoryTranscript,
        'elders': _elderNames.isEmpty ? '未留名' : _elderNames.join('、'),
        'imagePath': _currentImagePath,
        'createdAt': now.toIso8601String(),
        'keywords': _keywords,
        'turns': _turns.map((turn) => turn.toJson()).toList(),
        'imageVersions': _sessionImages.toList(),
        if (_selectedTopic?.topicId != null) 'topicId': _selectedTopic!.topicId,
      };
      await _memories.save(_memoryId ??= _memories.newId(), data);
      _saved = true;
      AppLog.instance.record(
        LogArea.history,
        LogEvent.saved,
        durationMs: saveWatch.elapsedMilliseconds,
      );
      return true;
    } catch (_) {
      AppLog.instance.record(
        LogArea.history,
        LogEvent.failed,
        durationMs: saveWatch.elapsedMilliseconds,
      );
      _errorMessage = '回憶保存失敗，請重試。';
      return false;
    } finally {
      _saving = false;
      _notify();
    }
  }

  Future<void> leave() async {
    _closed = true;
    _introductionRevision++;
    _session++;
    _cancelAi();
    _activeJob?.cancel();
    _busy = false;
    _isTranscribing = false;
    await _stopAllAudio();
    await _clearPendingAudio();
    if (_sessionImages.isNotEmpty) {
      await _memories.discardImages(_sessionImages);
    }
  }

  Future<void> _submitDebugAudio(DebugAudioSlot slot) async {
    if (_disposed || _closed || _busy || _isTranscribing || _isRecording) {
      return;
    }
    _busy = true;
    _errorMessage = null;
    final session = _session;
    String? copy;
    _notify();
    try {
      await _stopAllAudio();
      if (!_isCurrent(session)) return;
      await _clearPendingAudio();
      if (!_isCurrent(session)) return;
      _lastText = '';
      _interrupted = false;
      _audioWarning = null;
      copy = await _debugAudioSource!.take(slot);
      if (!_isCurrent(session)) {
        await File(copy).delete();
        return;
      }
      _pendingAudio = [copy];
      _busy = false;
      await retryTranscription();
    } catch (error) {
      if (!_isCurrent(session)) return;
      _errorMessage = error is DebugAudioException
          ? error.message
          : '測試音檔處理失敗。';
    } finally {
      if (_isCurrent(session)) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> _startRecording() async {
    if (_busy || _isTranscribing || _isRecording) return false;
    _busy = true;
    final requestSession = _session;
    try {
      await _clearPendingAudio();
      if (!_isCurrent(requestSession)) return false;
      _lastText = '';
      _interrupted = false;
      _audioWarning = null;
      _errorMessage = null;
      final voice = _ensureVoice();
      await voice.stopCurrentPlayback();
      await voice.stopActiveAudioOperations();
      if (!_isCurrent(requestSession)) return false;
      final key = _stage == LifeStage.introduction
          ? 'VOICE_INTRO_SILENCE_SECONDS'
          : 'VOICE_CHAT_SILENCE_SECONDS';
      final seconds =
          double.tryParse(ReminiCareConfig.getValue(key)) ??
          (_stage == LifeStage.introduction ? 3 : 6);
      final started = await voice.startChatFlow(
        silenceTimeout: Duration(milliseconds: (seconds * 1000).round()),
        maximumDuration: Duration(
          seconds: int.tryParse(ReminiCareConfig.maxRecordLimit) ?? 180,
        ),
      );
      if (!_isCurrent(requestSession) || !started) return false;
      _isRecording = true;
      _recordSeconds = 0;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_disposed || !_isRecording) return timer.cancel();
        _recordSeconds++;
        _notify();
        if (_recordSeconds >=
            (int.tryParse(ReminiCareConfig.maxRecordLimit) ?? 180)) {
          unawaited(voice.forceEndChat());
        }
      });
      return true;
    } catch (error) {
      if (!_isCurrent(requestSession)) return false;
      _isRecording = false;
      _errorMessage = error is SttException ? error.message : '無法啟動麥克風，請重試。';
      _notify();
      return false;
    } finally {
      if (_isCurrent(requestSession)) _busy = false;
    }
  }

  Future<void> completeRecording(List<String> paths) async {
    if (_disposed || _busy) return;
    _isRecording = false;
    _recordTimer?.cancel();
    _pendingAudio = paths;
    if (paths.isEmpty) {
      _errorMessage = '錄音未成功儲存，請重新錄音。';
      _introductionState = IntroductionState.ready;
      _notify();
      return;
    }
    await retryTranscription();
  }

  Future<void> retryTranscription() async {
    if (_disposed || _busy || _pendingAudio.isEmpty) return;
    _busy = true;
    _isTranscribing = true;
    _errorMessage = null;
    if (_stage == LifeStage.introduction) {
      _introductionState = IntroductionState.processing;
    }
    _notify();
    final requestSession = _session;
    try {
      final paths = [..._pendingAudio];
      final text = await _transcribe(paths);
      if (!_isCurrent(requestSession)) return;
      await _clearPendingAudio();
      if (!_isCurrent(requestSession)) return;
      _interrupted = false;
      _audioWarning = null;
      if (text.trim().isEmpty) {
        _errorMessage = '沒有辨識到語音，請重新錄音。';
        if (_stage == LifeStage.introduction) {
          _introductionState = IntroductionState.ready;
        }
        return;
      }

      if (_stage == LifeStage.introduction) {
        _lastText = text;
        _introductionState = IntroductionState.processing;
        _notify();
        try {
          final name = await _ai.extractElderName(text);
          if (!_isCurrent(requestSession)) return;
          _currentElderName = name;
        } catch (_) {
          if (!_isCurrent(requestSession)) return;
          _currentElderName = '';
          _errorMessage = '沒有確認到您的姓氏，請再介紹一次，並說明希望怎麼稱呼您。';
          _introductionState = IntroductionState.ready;
          return;
        }
        if (!_isCurrent(requestSession)) return;
        _introductionState = IntroductionState.confirmed;
        _notify();
        return;
      }

      _lastText = text;
      _lastWasRevision = _stage == LifeStage.revisionRecording;
      _turns.add(
        ConversationTurn(
          question: _currentQuestion,
          text: text,
          kind: _lastWasRevision
              ? ConversationTurnKind.correction
              : ConversationTurnKind.memory,
          createdAt: DateTime.now(),
          imagePath: _currentImagePath,
        ),
      );
      _transcript = memoryTranscript;
      _isTranscribing = false;
      if (_stage == LifeStage.revisionRecording) {
        await _reviseImage(requestSession, text);
      } else {
        await _createMemoryImage(requestSession, memoryTranscript);
      }
    } catch (error) {
      if (!_isCurrent(requestSession)) return;
      _errorMessage = error is SttException
          ? error.message
          : '語音辨識失敗，請重試或重新錄音。';
      if (_stage == LifeStage.introduction) {
        _introductionState = IntroductionState.ready;
      }
    } finally {
      if (_isCurrent(requestSession)) {
        _busy = false;
        _isTranscribing = false;
        _notify();
      }
    }
  }

  Future<String> _transcribe(List<String> paths) async {
    final requestSession = _session;
    final parts = <String>[];
    for (final path in paths) {
      if (!_isCurrent(requestSession)) {
        throw const SttException(SttErrorKind.cancelled, '已取消辨識。');
      }
      final job = _stt is JobSttService
          ? (_stt as JobSttService).createJob(path)
          : SpeechRecognitionJob(
              run: (_) => _stt.transcribeResult(path),
              abort: () {},
            );
      _activeJob = job;
      final subscription = job.progress.listen((progress) {
        if (!_isCurrent(requestSession)) return;
        _transcriptionComplete = progress.complete;
        _transcriptionTotal = progress.total;
        _notify();
      });
      _jobProgress = subscription;
      final result = await job.result;
      await subscription.cancel();
      if (identical(_jobProgress, subscription)) _jobProgress = null;
      if (identical(_activeJob, job)) _activeJob = null;
      if (result.error != null) throw result.error!;
      if (!result.isSilent) parts.add(result.text.trim());
    }
    return parts.join('，');
  }

  Future<void> _clearPendingAudio() async {
    _activeJob?.cancel();
    _activeJob = null;
    final subscription = _jobProgress;
    _jobProgress = null;
    await subscription?.cancel();
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
    _stage = LifeStage.imageGenerating;
    _errorMessage = null;
    _notify();
    var scene = text.trim().isEmpty
        ? (_selectedTopic?.imagePrompt ?? '')
        : '${_selectedTopic?.imagePrompt ?? ''}. Personal memory: $text';
    var era = '1960s-1980s';
    var location = 'Taiwan';
    try {
      final data = await _ai.extractSceneData(text);
      if (!_isCurrent(requestSession)) return;
      _keywords = (data['keywords'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      scene = data['scene']?.toString() ?? scene;
      if (data['era'] is String && (data['era'] as String).trim().isNotEmpty) {
        era = data['era'];
      }
      if (data['location'] is String &&
          (data['location'] as String).trim().isNotEmpty) {
        location = data['location'];
      }
    } catch (_) {
      if (!_isCurrent(requestSession)) return;
      _keywords = text
          .split(RegExp(r'[，。\s]+'))
          .where((e) => e.length >= 2)
          .take(5)
          .toList();
    }
    try {
      final prompt = const NostalgicImagePromptBuilder().build(
        scene: scene,
        era: era,
        location: location,
      );
      if (!_isCurrent(requestSession)) return;
      final imagePath = await _image.generate(prompt: prompt);
      if (!_isCurrent(requestSession)) {
        await _memories.discardImages([imagePath]);
        return;
      }
      _sessionImages.add(imagePath);
      _currentImagePath = imagePath;
      _stage = LifeStage.evaluation;
    } catch (error) {
      if (!_isCurrent(requestSession)) return;
      _errorMessage = error is AiServiceException
          ? error.message
          : '圖片產生失敗，請重試。';
      _stage = LifeStage.question;
    }
    _notify();
    if (_stage == LifeStage.evaluation) {
      unawaited(_play('這張照片像您的回憶嗎？', bothLanguages: true));
    }
  }

  Future<void> _reviseImage(int requestSession, String instruction) async {
    _stage = LifeStage.revisionGenerating;
    _errorMessage = null;
    _notify();
    try {
      String imagePath;
      if (canEditImage) {
        imagePath = await _image.edit(
          imagePath: _currentImagePath,
          instruction: instruction.trim().isEmpty
              ? 'Make the image better match the speaker’s memory while preserving the people and composition.'
              : instruction,
        );
      } else {
        final prompt = const NostalgicImagePromptBuilder().build(
          scene: '$memoryTranscript. Requested correction: $instruction',
        );
        imagePath = await _image.generate(prompt: prompt);
      }
      if (!_isCurrent(requestSession)) {
        await _memories.discardImages([imagePath]);
        return;
      }
      _sessionImages.add(imagePath);
      _currentImagePath = imagePath;
      _stage = LifeStage.evaluation;
    } catch (error) {
      if (!_isCurrent(requestSession)) return;
      _errorMessage = error is AiServiceException
          ? error.message
          : '圖片修改失敗，請重試。';
      _stage = LifeStage.revisionRecording;
    }
    _busy = false;
    _notify();
    if (_stage == LifeStage.evaluation) {
      unawaited(_play('這樣像嗎？', bothLanguages: true));
    }
  }

  String get _spokenText => switch (_stage) {
    LifeStage.introduction => '請大家介紹自己',
    LifeStage.question => _currentQuestion,
    LifeStage.evaluation => _hasExtension ? '這樣像嗎？' : '這張照片像您的回憶嗎？',
    LifeStage.revisionRecording => '哪裡不太像呢？請告訴我想修改的地方。',
    _ => _currentQuestion,
  };

  Future<void> _play(
    String text, {
    String? language,
    bool bothLanguages = false,
  }) async {
    if (text.isEmpty || _disposed) return;
    final session = _session;
    final outcome = await _ensureVoice().playLanguageSequence(
      texts: [text],
      languages: bothLanguages
          ? const ['台語', '中文']
          : [language ?? _selectedLanguage],
    );
    if (_isCurrent(session) && outcome == PlaybackOutcome.failed) {
      _audioWarning = '語音播放失敗，可以點選語言重播，或直接開始錄音。';
      _notify();
    }
  }

  VoiceAssistantManager _ensureVoice() {
    final existing = _voice;
    if (existing != null) return existing;
    final manager = (_voiceFactory?.call() ?? VoiceAssistantManager())
      ..onPlayingLanguageChanged = (language) {
        if (_disposed) return;
        _selectedLanguage = language;
        _notify();
      }
      ..onSpeechCompleted = (paths) {
        unawaited(completeRecording(paths));
      }
      ..onWarning = (message) {
        if (!_disposed) {
          _audioWarning = message;
          _notify();
        }
      }
      ..onRecordingFailed = () {
        if (!_disposed) {
          _isRecording = false;
          _recordTimer?.cancel();
          _errorMessage = '錄音操作失敗，請重新錄音。';
          _introductionState = IntroductionState.ready;
          _notify();
        }
      }
      ..onInterrupted = (paths) {
        if (_disposed) return;
        _isRecording = false;
        _recordTimer?.cancel();
        _pendingAudio = paths;
        _interrupted = paths.isNotEmpty;
        _introductionState = IntroductionState.ready;
        _audioWarning = '錄音已中斷，已保留可用音檔；可以辨識或重新錄音。';
        _notify();
      };
    _voice = manager;
    return manager;
  }

  Future<void> _stopAllAudio() async {
    _recordTimer?.cancel();
    _isRecording = false;
    await _voice?.stopCurrentPlayback();
    await _voice?.stopActiveAudioOperations();
  }

  Future<void> interruptAudio() async {
    if (_disposed) return;
    await _voice?.interrupt();
  }

  Future<void> retryLastStep() async {
    if (!canRetryLastStep || _disposed) return;
    _busy = true;
    _errorMessage = null;
    final session = _session;
    try {
      if (_stage == LifeStage.introduction) {
        final name = await _ai.extractElderName(_lastText);
        if (!_isCurrent(session)) return;
        _currentElderName = name;
        _introductionState = IntroductionState.confirmed;
      } else if (_lastWasRevision) {
        await _reviseImage(session, _lastText);
      } else {
        await _createMemoryImage(session, memoryTranscript);
      }
    } catch (_) {
      if (_isCurrent(session)) _errorMessage = '處理失敗，請重試或重新錄音。';
    } finally {
      if (_isCurrent(session)) {
        _busy = false;
        _notify();
      }
    }
  }

  bool _isCurrent(int value) => !_disposed && !_closed && value == _session;
  void _cancelAi() {
    if (!_servicesReady) return;
    _ai.cancelPending();
    final image = _image;
    if (image is CancelableAiWork) (image as CancelableAiWork).cancelPending();
  }

  LifeStage? _loggedStage;
  String? _loggedError;
  String? _loggedWarning;
  void _notify() {
    if (_disposed) return;
    if (_stage != _loggedStage) {
      _loggedStage = _stage;
      AppLog.instance.record(
        LogArea.flow,
        LogEvent.stageChanged,
        operationId: _session,
        detail: _stage.name,
      );
    }
    if (_errorMessage != _loggedError) {
      _loggedError = _errorMessage;
      if (_errorMessage != null) {
        AppLog.instance.record(
          LogArea.flow,
          LogEvent.failed,
          operationId: _session,
          detail: _stage.name,
        );
      }
    }
    if (_audioWarning != _loggedWarning) {
      _loggedWarning = _audioWarning;
      if (_audioWarning != null) {
        AppLog.instance.record(
          LogArea.flow,
          LogEvent.warning,
          operationId: _session,
        );
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _cancelAi();
    _activeJob?.cancel();
    _recordTimer?.cancel();
    _voice?.dispose();
    unawaited(_clearPendingAudio());
    if (!_closed && _sessionImages.isNotEmpty) {
      unawaited(
        _memories.discardImages(_sessionImages).catchError((Object _) {}),
      );
    }
    super.dispose();
  }
}
