import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:remini_care_ai_app/screens/life_screen/life_screen.dart';
import 'package:remini_care_ai_app/screens/app_log_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';
import 'package:remini_care_ai_app/services/api_services.dart';
import 'package:remini_care_ai_app/services/audio_services/wav_audio.dart';
import 'package:remini_care_ai_app/services/debug_flow.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/memory_repository.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:remini_care_ai_app/theme/remini_care_theme.dart';

const _live = bool.fromEnvironment('REMINICARE_LIVE_SERVICES');
const _manifest64 = String.fromEnvironment('REMINICARE_AUDIO_MANIFEST64');
const _output64 = String.fromEnvironment('REMINICARE_TEST_OUTPUT64');
String _decode(String value) => utf8.decode(base64Decode(value));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live fixed audio flow',
    (tester) async {
      if (!kDebugMode || !Platform.isWindows) {
        throw TestFailure('Live acceptance requires a Windows debug build.');
      }
      await tester.binding.setSurfaceSize(const Size(1366, 1024));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late LifeScreenController controller;
      var started = false;
      Directory? output;
      var step = 'setup';
      final sampleStats = <Map<String, Object>>[];
      final report = <Map<String, Object>>[];
      Future<void> waitFor(String stage, bool Function() ready) async {
        step = stage;
        final watch = Stopwatch()..start();
        while (!ready()) {
          if (controller.errorMessage != null ||
              watch.elapsed > const Duration(minutes: 15)) {
            throw TestFailure('Acceptance failed at stage $stage.');
          }
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        report.add({'stage': stage, 'elapsedMs': watch.elapsedMilliseconds});
        // A service can finish between frames; render the new stage before querying keys.
        await tester.pump(const Duration(milliseconds: 300));
        if (output != null) {
          // Private acceptance evidence, never printed or included in the anonymous report.
          await File('${output.path}/private-observations.json').writeAsString(
            jsonEncode({
              'stage': stage,
              'currentAddress': controller.currentElderName,
              'addresses': controller.elderNames,
              'turns': controller.turns.map((turn) => turn.toJson()).toList(),
            }),
          );
        }
      }

      Future<void> tap(String key) async {
        step = 'action-$key';
        await tester.pump(const Duration(milliseconds: 300));
        final finder = find.byKey(ValueKey(key));
        if (finder.evaluate().length != 1) {
          throw TestFailure('Missing action $key.');
        }
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      try {
        final source = await ManifestDebugAudioSource.load(
          _decode(_manifest64),
        );
        for (final entry in source.files.entries) {
          for (var i = 0; i < entry.value.length; i++) {
            final bytes = await File(entry.value[i]).readAsBytes();
            final wav = WavAudio.parse(bytes);
            if (wav.pcm.isEmpty) {
              throw const DebugAudioException('Empty sample.');
            }
            sampleStats.add({
              'slot': entry.key.name,
              'index': i + 1,
              'bytes': bytes.length,
              'durationMs': (wav.seconds * 1000).round(),
            });
          }
        }
        output = Directory(_decode(_output64)).absolute;
        if (await output.exists()) {
          throw TestFailure('Output directory must be new.');
        }
        await output.create(recursive: true);
        await ReminiCareConfig.loadConfig();
        if (ReminiCareConfig.validateProviderSettings({}) != null) {
          throw TestFailure(
            'Configure the selected providers before live acceptance.',
          );
        }
        final storage = output;
        final repository = MemoryRepository(
          directory: () async => storage,
          migrateLegacy: false,
        );
        final config = ApiServices().imageConfig;
        final store = LocalImageStore(directory: () async => storage);
        final IImageGenerationClient images = config.id == 'cloudflare'
            ? CloudflareWorkerImageClient(
                config: config,
                appToken: ReminiCareConfig.getValue(config.apiKeyReference),
                store: store,
              )
            : OpenAiCompatibleImageClient(
                config: config,
                apiKey: ReminiCareConfig.getValue(config.apiKeyReference),
                store: store,
              );
        controller = LifeScreenController(
          debugFixedFlow: true,
          debugAudioSource: source,
          memoryRepository: repository,
          imageService: images,
        );
        started = true;
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            builder: (_, child) =>
                AppLogOverlay(navigatorKey: navigatorKey, child: child!),
            theme: ReminiCareTheme.light,
            home: LifeScreen(controllerFactory: () => controller),
          ),
        );
        await waitFor(
          'topics',
          () => controller.stage == LifeStage.topicSelection,
        );
        if (!controller.debugFixedFlow) {
          throw TestFailure('Debug injection did not enable fixed flow.');
        }
        await tap('topic-street');
        final introductions = source.files[DebugAudioSlot.introduction]!;
        for (var i = 0; i < introductions.length; i++) {
          await tap('record-introduction');
          await waitFor(
            'introduction-${i + 1}',
            () => controller.introductionState == IntroductionState.confirmed,
          );
          await tap(
            i + 1 < introductions.length
                ? 'next-participant'
                : 'finish-introduction',
          );
        }
        await waitFor(
          'main-question',
          () => controller.stage == LifeStage.question,
        );
        if (controller.currentQuestion != '以前住的街上有哪些店？') {
          throw TestFailure('Main question changed.');
        }
        await tap('record-answer');
        await waitFor(
          'main-image',
          () => controller.stage == LifeStage.evaluation,
        );
        for (
          var i = 0;
          i < source.files[DebugAudioSlot.revision]!.length;
          i++
        ) {
          await tap('dislike');
          await tap('record-revision');
          await waitFor(
            'revision-${i + 1}',
            () => controller.stage == LifeStage.evaluation,
          );
        }
        await tap('like');
        await waitFor(
          'extension-question',
          () => controller.stage == LifeStage.question,
        );
        if (controller.currentQuestion != '有沒有最熟悉的鄰居？') {
          throw TestFailure('Extension question changed.');
        }
        await tap('record-answer');
        await waitFor(
          'extension-image',
          () => controller.stage == LifeStage.evaluation,
        );
        await tap('like');
        await waitFor('summary', () => controller.stage == LifeStage.summary);
        await tap('save-memory');
        await waitFor('saved', () => controller.isSaved);
        final records = await repository.load();
        if (records.length != 1 ||
            controller.turns.length !=
                2 + source.files[DebugAudioSlot.revision]!.length ||
            controller.memoryTranscript.isEmpty ||
            !await File(controller.currentImagePath).exists()) {
          throw TestFailure('Isolated saved memory is incomplete.');
        }
        await File('${output.path}/acceptance-report.json').writeAsString(
          jsonEncode({
            'status': 'passed',
            'stages': report,
            'samples': sampleStats,
          }),
        );
        binding.reportData = {
          'status': 'passed',
          'stages': report,
          'samples': sampleStats,
        };
      } catch (error) {
        // Do not include Provider messages, names, transcripts, or sample paths.
        binding.reportData = {
          'status': 'failed',
          'stage': step,
          'stages': report,
          'samples': sampleStats,
          'exceptionType': error.runtimeType.toString(),
          if (error is TestFailure &&
              RegExp(
                r'^Missing action [a-z-]+\.$',
              ).hasMatch(error.message ?? ''))
            'missingAction': step,
          'errorKind': error is DebugAudioException
              ? 'testAudio'
              : error is TestFailure
              ? 'acceptance'
              : 'unexpected',
        };
        if (output != null) {
          try {
            await File(
              '${output.path}/acceptance-report.json',
            ).writeAsString(jsonEncode(binding.reportData));
          } catch (_) {
            /* Diagnostics must not mask the original failure. */
          }
        }
        throw TestFailure(
          'Live acceptance failed at stage $step. Check the local App; no automatic retry was sent.',
        );
      } finally {
        if (started) await controller.leave();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    // This live harness uses widget keys, not accessibility semantics. Avoid
    // the Windows engine retaining the test-created semantics request.
    semanticsEnabled: false,
    skip: !_live || _manifest64.isEmpty || _output64.isEmpty,
    timeout: const Timeout(Duration(hours: 2)),
  );
}
