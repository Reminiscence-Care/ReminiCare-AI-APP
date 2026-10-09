import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/life_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';
import 'package:remini_care_ai_app/services/ai/ai_models.dart';
import 'package:remini_care_ai_app/services/ai/llm_client.dart';
import 'package:remini_care_ai_app/services/ai/reminiscence_ai_service.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/audio_services/audio_ports.dart';
import 'package:remini_care_ai_app/services/audio_services/stt_result.dart';
import 'package:remini_care_ai_app/services/audio_services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/audio_services/wav_audio.dart';
import 'package:remini_care_ai_app/services/debug_flow.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/memory_repository.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'audio_lifecycle_test.dart' show FakeRecorder, FakePlayback;

class _Llm implements LlmClient {
  int calls = 0;
  @override
  Future<String> complete({
    required List<LlmMessage> messages,
    double temperature = 0.6,
    int maxTokens = 500,
    bool jsonObject = false,
  }) async {
    calls++;
    if (messages.first.content.contains('scene')) {
      return '{"scene":"test scene","era":"1970s","location":"Taiwan","keywords":["街道"]}';
    }
    if (messages.last.content.startsWith('先前問題')) return '動態問題';
    if (messages.first.content.contains('姓')) {
      return '{"surname":"陳","title":null}';
    }
    return '{"topics":[]}';
  }
}

class _Stt implements ISTTService {
  final paths = <String>[];
  bool fail = false;
  Completer<String>? gate;
  @override
  Future<String?> transcribe(String path) async {
    paths.add(path);
    if (fail) throw const SttException(SttErrorKind.timeout, '測試逾時');
    return gate?.future ?? Future.value('我姓陳，測試回憶');
  }
}

class _Tts implements ITTSService {
  @override
  Future<Uint8List?> generateSpeech(String text, String language) async => null;
}

class _Images implements IImageGenerationClient {
  _Images(this.root);
  final Directory root;
  int calls = 0;
  bool fail = false;
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
    if (fail) throw StateError('fake image failure');
    final file = File('${root.path}/reminicare_images/test-${calls++}.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodePng(img.Image(width: 2, height: 2)));
    return file.path;
  }

  @override
  Future<String> edit({
    required String imagePath,
    required String instruction,
  }) => generate(prompt: instruction);
}

class _GatedSource implements DebugAudioSource {
  final gate = Completer<String>();
  final entered = Completer<void>();
  int calls = 0;
  @override
  Future<String> take(DebugAudioSlot slot) {
    calls++;
    if (!entered.isCompleted) entered.complete();
    return gate.future;
  }
}

class _SequenceVoice extends VoiceAssistantManager {
  _SequenceVoice()
    : super(
        recorder: FakeRecorder(),
        playback: FakePlayback(),
        tts: _Tts(),
        activate: () async {},
      );
  final sequences = <List<String>>[];
  @override
  Future<PlaybackOutcome> playLanguageSequence({
    required List<String> texts,
    required List<String> languages,
    int repeatCount = 1,
    int gapMs = 300,
    int partGapMs = 150,
  }) async {
    sequences.add(List.of(languages));
    return PlaybackOutcome.completed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Directory root;
  late File original;
  late _Llm llm;
  late _Stt stt;
  late _Images images;
  late FakeRecorder recorder;
  late FakePlayback playback;
  late VoiceAssistantManager voice;
  LifeScreenController? controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'secure_storage_migration_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (_) async => null);
    root = await Directory.systemTemp.createTemp('reminicare_debug_test_');
    original = File('${root.path}/original.wav');
    await original.writeAsBytes(WavAudio(Uint8List(3200)).encode());
    llm = _Llm();
    stt = _Stt();
    images = _Images(root);
    recorder = FakeRecorder();
    playback = FakePlayback();
    voice = VoiceAssistantManager(
      recorder: recorder,
      playback: playback,
      tts: _Tts(),
      createPath: () async => '${root.path}/recording.wav',
      activate: () async {},
    );
  });
  tearDown(() async {
    await controller?.leave();
    controller?.dispose();
    controller = null;
    await voice.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    await root.delete(recursive: true);
  });
  ManifestDebugAudioSource source() => ManifestDebugAudioSource({
    for (final slot in DebugAudioSlot.values) slot: [original.path],
  }, temporary: () async => Directory('${root.path}/temporary'));
  Future<LifeScreenController> create({
    bool? fixed = true,
    DebugAudioSource? audio,
  }) async {
    final c = LifeScreenController(
      debugFixedFlow: fixed,
      debugAudioSource: audio,
      aiService: ReminiscenceAiService(llm),
      sttService: stt,
      imageService: images,
      voiceFactory: () => voice,
      memoryRepository: MemoryRepository(
        directory: () async => root,
        migrateLegacy: false,
      ),
    );
    controller = c;
    await c.initialize();
    return c;
  }

  test('introduction automatically requests Taiwanese then Chinese', () async {
    await voice.close();
    final sequence = _SequenceVoice();
    voice = sequence;
    final c = await create();
    c.selectTopic(c.topics.first);
    await Future<void>.delayed(Duration.zero);
    expect(sequence.sequences, [
      ['台語', '中文'],
    ]);
  });
  test('fixed topics refresh identically and never enrich questions', () async {
    final c = await create();
    expect(c.debugFixedFlow, isTrue);
    expect(c.topics.map((t) => t.topicId), DebugFlow.topicIds);
    expect(c.topics.first.question, '以前住的街上有哪些店？');
    final paths = c.topics.map((t) => t.thumbnailPath).toList();
    await c.refreshTopics();
    expect(c.topics.map((t) => t.topicId), DebugFlow.topicIds);
    expect(c.topics.map((t) => t.thumbnailPath), paths);
    expect(llm.calls, 0);
    c.selectTopic(c.topics.first);
    c.restoreForTesting(stage: LifeStage.evaluation);
    await c.chooseLike();
    expect(c.currentQuestion, '有沒有最熟悉的鄰居？');
    expect(c.hasExtension, isTrue);
    expect(llm.calls, 0);
    c.restoreForTesting(stage: LifeStage.evaluation);
    await c.chooseLike();
    expect(c.stage, LifeStage.summary);
  });
  test('CLI override does not persist and mode stays locked', () async {
    final c = await create();
    expect(ReminiCareConfig.debugFixedFlow, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(
        ReminiCareConfig.debugFlowKey,
      ),
      isNull,
    );
    await ReminiCareConfig.saveConfig({ReminiCareConfig.debugFlowKey: 'false'});
    await c.initialize();
    expect(c.debugFixedFlow, isTrue);
  });
  test(
    'saved switch loads next session and explicit false override wins',
    () async {
      await ReminiCareConfig.saveConfig({
        ReminiCareConfig.debugFlowKey: 'true',
      });
      await ReminiCareConfig.loadConfig();
      expect(ReminiCareConfig.debugFixedFlow, isTrue);
      final c = await create(fixed: false);
      expect(c.debugFixedFlow, isFalse);
      expect(llm.calls, 1);
      c.selectTopic(c.topics.first);
      c.restoreForTesting(stage: LifeStage.evaluation);
      await c.chooseLike();
      expect(c.currentQuestion, '動態問題');
      expect(llm.calls, 2);
      expect(ReminiCareConfig.debugFixedFlow, isTrue);
    },
  );
  test(
    'manual debug still starts microphone when no source injected',
    () async {
      final c = await create();
      c.selectTopic(c.topics.first);
      await c.startIntroductionRecording();
      expect(recorder.starts, 1);
      expect(c.isRecording, isTrue);
    },
  );
  test(
    'sample uses owned copy, stops playback, and retry keeps same copy',
    () async {
      final c = await create(audio: source());
      c.selectTopic(c.topics.first);
      c.restoreForTesting(stage: LifeStage.question);
      stt.fail = true;
      await c.startAnswerRecording();
      expect(recorder.starts, 0);
      expect(playback.stops, greaterThan(0));
      expect(c.canRetryTranscription, isTrue);
      final copy = stt.paths.single;
      expect(copy, isNot(original.path));
      expect(await File(copy).exists(), isTrue);
      stt.fail = false;
      await c.retryTranscription();
      expect(stt.paths, [copy, copy]);
      expect(c.stage, LifeStage.evaluation);
      expect(await File(copy).exists(), isFalse);
      expect(await original.exists(), isTrue);
      expect(c.turns, hasLength(1));
      images.fail = true;
      await c.chooseLike();
      await c.startAnswerRecording();
      expect(c.canRetryLastStep, isTrue);
      images.fail = false;
      await c.retryLastStep();
      expect(stt.paths, hasLength(3));
      expect(c.turns, hasLength(2));
    },
  );
  test(
    'double start consumes only one sample; late copy after leave is deleted',
    () async {
      final audio = _GatedSource();
      final c = await create(audio: audio);
      c.selectTopic(c.topics.first);
      c.restoreForTesting(stage: LifeStage.question);
      final first = c.startAnswerRecording();
      await audio.entered.future;
      await c.startAnswerRecording();
      expect(audio.calls, 1);
      await c.leave();
      final copy = await original.copy('${root.path}/late.wav');
      audio.gate.complete(copy.path);
      await first;
      expect(stt.paths, isEmpty);
      expect(await copy.exists(), isFalse);
      expect(await original.exists(), isTrue);
    },
  );
  test('dispose during copy cannot start STT or revive UI', () async {
    final audio = _GatedSource();
    final c = await create(audio: audio);
    c.selectTopic(c.topics.first);
    c.restoreForTesting(stage: LifeStage.question);
    final first = c.startAnswerRecording();
    await audio.entered.future;
    c.dispose();
    controller = null;
    final copy = await original.copy('${root.path}/disposed.wav');
    audio.gate.complete(copy.path);
    await first;
    expect(stt.paths, isEmpty);
    expect(await copy.exists(), isFalse);
  });
  test('old STT after leave cannot add turns or generate an image', () async {
    final c = await create(audio: source());
    c.selectTopic(c.topics.first);
    c.restoreForTesting(stage: LifeStage.question);
    stt.gate = Completer<String>();
    final first = c.startAnswerRecording();
    while (stt.paths.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await c.leave();
    stt.gate!.complete('old result');
    await first;
    expect(c.turns, isEmpty);
    expect(images.calls, 0);
    expect(await original.exists(), isTrue);
  });
  test(
    'invalid, missing and exhausted samples fail visibly without microphone',
    () async {
      await original.writeAsBytes([1, 2, 3]);
      final c = await create(audio: source());
      c.selectTopic(c.topics.first);
      await c.startIntroductionRecording();
      expect(c.errorMessage, contains('PCM16'));
      expect(stt.paths, isEmpty);
      expect(recorder.starts, 0);
      await original.delete();
      await c.startIntroductionRecording();
      expect(c.errorMessage, isNotNull);
      expect(stt.paths, isEmpty);
      final empty = ManifestDebugAudioSource({});
      await expectLater(
        empty.take(DebugAudioSlot.answer),
        throwsA(isA<DebugAudioException>()),
      );
    },
  );
  test(
    'manifest paths resolve beside manifest, originals remain unchanged',
    () async {
      final manifest = File('${root.path}/scenario.json');
      await manifest.writeAsString(
        jsonEncode({
          'introduction': ['original.wav'],
          'answer': ['original.wav'],
          'extension': ['original.wav'],
        }),
      );
      final audio = await ManifestDebugAudioSource.load(
        manifest.path,
        temporary: () async => Directory("${root.path}/temporary"),
      );
      expect(
        File(audio.files[DebugAudioSlot.answer]!.single).absolute.uri,
        original.absolute.uri,
      );
      final copy = await audio.take(DebugAudioSlot.answer);
      expect(await File(copy).readAsBytes(), await original.readAsBytes());
      await File(copy).delete();
      await expectLater(
        audio.take(DebugAudioSlot.answer),
        throwsA(isA<DebugAudioException>()),
      );
      expect(await original.exists(), isTrue);
      await manifest.writeAsString('{}');
      await expectLater(
        ManifestDebugAudioSource.load(manifest.path),
        throwsA(isA<DebugAudioException>()),
      );
    },
  );
  test('isolated repository skips legacy migration', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('chat_memories', [
      jsonEncode({'topic': 'legacy', 'content': 'synthetic'}),
    ]);
    final isolated = MemoryRepository(
      directory: () async => root,
      migrateLegacy: false,
    );
    expect(await isolated.load(), isEmpty);
    expect(
      jsonDecode(
        await File(
          '${root.path}/reminicare_memories/legacy-backup.json',
        ).readAsString(),
      ),
      isEmpty,
    );
    expect(prefs.getStringList('chat_memories'), hasLength(1));
  });
  testWidgets(
    'stable UI actions complete injected audio flow and isolated save',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 1024));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late LifeScreenController c;
      await tester.runAsync(() async {
        final audio = source();
        audio.files[DebugAudioSlot.introduction]!.add(original.path);
        c = await create(audio: audio);
        await tester.pumpWidget(
          MaterialApp(home: LifeScreen(controllerFactory: () => c)),
        );
        await ReminiCareConfig.loadConfig();
      });
      await tester.pumpAndSettle();
      Future<void> tap(String key, bool Function() ready) async {
        final finder = find.byKey(ValueKey(key));
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(finder);
          final timer = Stopwatch()..start();
          while (!ready()) {
            if (c.errorMessage != null ||
                timer.elapsed > const Duration(seconds: 5)) {
              fail('Fake UI flow did not complete action $key');
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        });
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const ValueKey('debug-flow-banner')), findsOneWidget);
      await tap('topic-street', () => c.stage == LifeStage.introduction);
      await tap(
        'record-introduction',
        () => c.introductionState == IntroductionState.confirmed,
      );
      await tap(
        'next-participant',
        () => c.introductionState == IntroductionState.ready,
      );
      await tap(
        'record-introduction',
        () => c.introductionState == IntroductionState.confirmed,
      );
      await tap('finish-introduction', () => c.stage == LifeStage.question);
      expect(c.elderNames, hasLength(2));
      await tap('record-answer', () => c.stage == LifeStage.evaluation);
      await tap('dislike', () => c.stage == LifeStage.revisionRecording);
      await tap('record-revision', () => c.stage == LifeStage.evaluation);
      await tap('like', () => c.stage == LifeStage.question);
      expect(c.currentQuestion, '有沒有最熟悉的鄰居？');
      await tap('record-answer', () => c.stage == LifeStage.evaluation);
      await tap('like', () => c.stage == LifeStage.summary);
      await tap('save-memory', () => c.isSaved);
      expect(stt.paths, hasLength(5));
      expect(c.turns, hasLength(3));
      expect(await tester.runAsync(original.exists), isTrue);
      await tester.runAsync(() async => c.leave());
      await tester.runAsync(() async {
        await voice.close();
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      controller = null;
    },
  );
  testWidgets('debug switch saves only on apply and reloads', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secure,
          (call) async => call.method == 'read' ? 'fake-test-key' : null,
        );
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await ReminiCareConfig.loadConfig();
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('debug-fixed-flow'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(ReminiCareConfig.debugFixedFlow, isFalse);
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(ReminiCareConfig.validateProviderSettings({}), isNull);
    await tester.runAsync(() async {
      await tester.tap(find.text('儲存並套用'));
      await ReminiCareConfig.loadConfig();
    });
    await tester.pumpAndSettle();
    expect(find.text('ReminiCare AI 設定'), findsNothing);
    await tester.pumpAndSettle();
    expect(ReminiCareConfig.debugFixedFlow, isTrue);
    await tester.runAsync(ReminiCareConfig.loadConfig);
    expect(ReminiCareConfig.debugFixedFlow, isTrue);
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
