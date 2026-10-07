import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/models/conversation_turn.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';
import 'package:remini_care_ai_app/services/ai/ai_models.dart';
import 'package:remini_care_ai_app/services/ai/ai_service_exception.dart';
import 'package:remini_care_ai_app/services/ai/llm_client.dart';
import 'package:remini_care_ai_app/services/ai/reminiscence_ai_service.dart';
import 'package:remini_care_ai_app/services/audio_services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/memory_repository.dart';
import 'audio_lifecycle_test.dart' show FakeRecorder, FakePlayback;

class _Llm implements LlmClient {
  Completer<String>? extended;
  final List<String> scenes = [];
  @override
  Future<String> complete({
    required List<LlmMessage> messages,
    double temperature = 0.6,
    int maxTokens = 500,
    bool jsonObject = false,
  }) async {
    if (messages.first.content.contains('scene')) {
      scenes.add(messages.last.content);
      return '{"scene":"memory scene","era":"1950s","location":"Tainan","keywords":["回憶"]}';
    }
    if (messages.last.content.startsWith('先前問題')) {
      return extended?.future ?? Future.value('還記得什麼？');
    }
    return '{"topics":[]}';
  }
}

class _Images implements IImageGenerationClient {
  _Images(this.root);
  final Directory root;
  int calls = 0;
  bool fail = false;
  String lastPrompt = '';
  @override
  ImageProviderConfig get config => const ImageProviderConfig(
    id: 'fake',
    displayName: 'Fake',
    baseUrl: 'https://example.test',
    generationModel: 'fake',
    apiKeyReference: 'fake',
    capabilities: {
      ProviderCapability.imageGeneration,
      ProviderCapability.imageEditing,
    },
  );
  @override
  Future<String> generate({required String prompt}) async {
    calls++;
    lastPrompt = prompt;
    if (fail) {
      throw const AiServiceException(AiServiceErrorKind.timeout, '測試生圖失敗');
    }
    final file = File('${root.path}/reminicare_images/generated-$calls.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return file.path;
  }

  @override
  Future<String> edit({
    required String imagePath,
    required String instruction,
  }) => generate(prompt: instruction);
}

class _Stt implements ISTTService {
  int calls = 0;
  final List<String> texts = [];
  @override
  Future<String?> transcribe(String path) async {
    calls++;
    return texts.removeAt(0);
  }
}

class _SilentTts implements ITTSService {
  @override
  Future<Uint8List?> generateSpeech(String text, String language) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Directory root;
  late _Llm llm;
  late _Images images;
  late _Stt stt;
  late FakeRecorder recorder;
  late VoiceAssistantManager voice;
  late LifeScreenController controller;
  late MemoryRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'secure_storage_migration_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (_) async => null);
    root = await Directory.systemTemp.createTemp(
      'reminicare_controller_stability_',
    );
    llm = _Llm();
    images = _Images(root);
    stt = _Stt();
    recorder = FakeRecorder();
    voice = VoiceAssistantManager(
      recorder: recorder,
      playback: FakePlayback(),
      tts: _SilentTts(),
      createPath: () async => '${root.path}/recording.wav',
      activate: () async {},
    );
    repository = MemoryRepository(directory: () async => root);
    controller = LifeScreenController(
      aiService: ReminiscenceAiService(llm),
      imageService: images,
      sttService: stt,
      voiceFactory: () => voice,
      memoryRepository: repository,
    );
    await controller.initialize();
  });
  tearDown(() async {
    await controller.leave();
    controller.dispose();
    await voice.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    await root.delete(recursive: true);
  });
  Future<void> submit(String text) async {
    stt.texts.add(text);
    final file = File('${root.path}/input-${stt.calls}.wav');
    await file.writeAsBytes([1, 2, 3]);
    await controller.completeRecording([file.path]);
  }

  test('late extended question cannot move summary back to question', () async {
    controller.restoreForTesting(stage: LifeStage.evaluation);
    llm.extended = Completer<String>();
    final choosing = controller.chooseLike();
    await controller.finishSession();
    llm.extended!.complete('late question');
    await choosing;
    expect(controller.stage, LifeStage.summary);
    expect(controller.currentQuestion, isNot('late question'));
  });
  test('returning during native start does not revive recording UI', () async {
    controller.restoreForTesting(stage: LifeStage.introduction);
    recorder.startGate = Completer<void>();
    final starting = controller.startIntroductionRecording();
    while (recorder.starts == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final leaving = controller.leave();
    recorder.startGate!.complete();
    await Future.wait([starting, leaving]);
    expect(controller.isRecording, isFalse);
    expect(controller.recordSeconds, 0);
    expect(recorder.stops, 1);
  });
  test('pending extension cannot also start a competing correction', () async {
    controller.restoreForTesting(stage: LifeStage.evaluation);
    llm.extended = Completer<String>();
    final choosing = controller.chooseLike();
    controller.chooseDislike();
    expect(controller.stage, LifeStage.evaluation);
    llm.extended!.complete('延伸問題');
    await choosing;
    expect(controller.stage, LifeStage.question);
  });
  test(
    'revision does not overwrite memory and prompt uses returned era/location',
    () async {
      controller.restoreForTesting(
        stage: LifeStage.question,
        currentQuestion: '第一個問題',
      );
      await submit('小時候和爸爸搭火車');
      expect(images.lastPrompt, contains('1950s Tainan'));
      controller.restoreForTesting(
        stage: LifeStage.question,
        currentQuestion: '延伸問題',
      );
      await submit('還買了便當');
      expect(llm.scenes.last, contains('小時候和爸爸搭火車，還買了便當'));
      controller.restoreForTesting(stage: LifeStage.revisionRecording);
      await submit('把衣服改成藍色');
      expect(controller.transcript, '小時候和爸爸搭火車，還買了便當');
      expect(controller.turns.last.kind, ConversationTurnKind.correction);
      await controller.finishSession();
      await Future.wait([controller.saveMemory(), controller.saveMemory()]);
      final records = await repository.load();
      expect(records, hasLength(1));
      expect(records.single['content'], controller.memoryTranscript);
      expect((records.single['turns'] as List).length, 3);
    },
  );
  test(
    'failed image can be retried without STT or duplicate conversation turn',
    () async {
      controller.restoreForTesting(stage: LifeStage.question);
      images.fail = true;
      await submit('一起收割稻子');
      expect(controller.canRetryLastStep, isTrue);
      expect(stt.calls, 1);
      images.fail = false;
      await controller.retryLastStep();
      expect(stt.calls, 1);
      expect(controller.turns, hasLength(1));
      expect(controller.stage, LifeStage.evaluation);
    },
  );
  test(
    'interruption leaves recorded audio pending without automatically calling STT',
    () async {
      controller.restoreForTesting(stage: LifeStage.question);
      await controller.startAnswerRecording();
      await controller.interruptAudio();
      expect(controller.isRecording, isFalse);
      expect(controller.hasInterruptedRecording, isTrue);
      expect(controller.canRetryTranscription, isTrue);
      expect(stt.calls, 0);
      stt.texts.add('保留的回憶');
      await controller.retryTranscription();
      expect(stt.calls, 1);
      expect(controller.stage, LifeStage.evaluation);
    },
  );
}
