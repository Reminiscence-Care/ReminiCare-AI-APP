import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/services/audio_services/audio_ports.dart';
import 'package:remini_care_ai_app/services/audio_services/recording_controller.dart';
import 'package:remini_care_ai_app/services/audio_services/tts_cache.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/audio_services/wav_audio.dart';

class FakeRecorder implements RecorderPort {
  final states = StreamController<bool>.broadcast();
  bool permission = true;
  bool failAmplitude = false;
  bool failStop = false;
  Completer<void>? startGate;
  String? path;
  int starts = 0;
  int stops = 0;
  int samples = 0;
  double Function(int) db = (_) => -60;
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<void> start(String value) async {
    starts++;
    path = value;
    await startGate?.future;
    await File(value).writeAsBytes(WavAudio(Uint8List(3200)).encode());
    states.add(true);
  }

  @override
  Future<String?> stop() async {
    stops++;
    if (failStop) throw StateError('stop');
    states.add(false);
    return path;
  }

  @override
  Future<double> amplitude() async {
    if (failAmplitude) throw StateError('amplitude');
    return db(samples++);
  }

  @override
  Stream<bool> get recording => states.stream;
  @override
  Future<void> dispose() async {
    await states.close();
  }
}

class FakePlayback implements PlaybackPort {
  final events = StreamController<void>.broadcast();
  int plays = 0;
  int stops = 0;
  bool fail = false;
  @override
  Stream<void> get completed => events.stream;
  @override
  Future<void> play(String path) async {
    plays++;
    if (fail) throw StateError('play');
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    await events.close();
  }
}

class FakeTts implements ITTSService {
  int calls = 0;
  @override
  Future<Uint8List?> generateSpeech(String text, String language) async {
    calls++;
    return WavAudio(Uint8List(3200)).encode();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('reminicare_lifecycle_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  RecordingController recorder(FakeRecorder port) => RecordingController(
    port,
    createPath: () async => '${root.path}/audio.wav',
    activate: () async {},
    sampleInterval: const Duration(milliseconds: 5),
  );

  test(
    'start cancellation serializes stop and removes cancelled recording',
    () async {
      final port = FakeRecorder()..startGate = Completer<void>();
      final control = recorder(port);
      var completions = 0;
      control.onCompleted = (_) => completions++;
      final starting = control.start(
        silenceTimeout: const Duration(seconds: 3),
        maximumDuration: const Duration(seconds: 20),
      );
      while (port.starts == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final stopping = control.stop(RecordingStopReason.cancelled);
      port.startGate!.complete();
      expect(await starting, isFalse);
      await stopping;
      expect(port.stops, 1);
      expect(await File('${root.path}/audio.wav').exists(), isFalse);
      expect(completions, 0);
      await control.dispose();
    },
  );
  test('quick starts and simultaneous stops finalize only once', () async {
    final port = FakeRecorder();
    final control = recorder(port);
    var completions = 0;
    control.onCompleted = (_) => completions++;
    final starts = await Future.wait([
      control.start(
        silenceTimeout: const Duration(seconds: 3),
        maximumDuration: const Duration(seconds: 20),
      ),
      control.start(
        silenceTimeout: const Duration(seconds: 3),
        maximumDuration: const Duration(seconds: 20),
      ),
    ]);
    expect(starts.where((ok) => ok).length, 1);
    await Future.wait([
      control.stop(RecordingStopReason.manual),
      control.stop(RecordingStopReason.silence),
    ]);
    expect(completions, 1);
    expect(port.stops, 1);
    await control.dispose();
  });
  test(
    'immediate speech is detected before noise calibration completes',
    () async {
      final port = FakeRecorder()..db = (i) => i < 3 ? -25 : -60;
      final control = recorder(port);
      final result = Completer<RecordingResult>();
      control.onCompleted = result.complete;
      await control.start(
        silenceTimeout: const Duration(milliseconds: 30),
        maximumDuration: const Duration(seconds: 2),
      );
      expect(
        (await result.future.timeout(const Duration(seconds: 1))).reason,
        RecordingStopReason.silence,
      );
      await control.dispose();
    },
  );
  test(
    'amplitude failure falls back to manual while maximum duration stays active',
    () async {
      final port = FakeRecorder()..failAmplitude = true;
      final control = recorder(port);
      final warning = Completer<String>();
      final result = Completer<RecordingResult>();
      control.onWarning = warning.complete;
      control.onCompleted = result.complete;
      await control.start(
        silenceTimeout: const Duration(seconds: 3),
        maximumDuration: const Duration(milliseconds: 120),
      );
      expect(await warning.future, contains('說完了'));
      expect((await result.future).reason, RecordingStopReason.maximumDuration);
      await control.dispose();
    },
  );
  test('permission denied and native stop failure are visible', () async {
    final port = FakeRecorder()..permission = false;
    final control = recorder(port);
    await expectLater(
      control.start(
        silenceTimeout: const Duration(seconds: 3),
        maximumDuration: const Duration(seconds: 20),
      ),
      throwsException,
    );
    expect(control.state, RecordingState.failed);
    port.permission = true;
    port.failStop = true;
    await control.start(
      silenceTimeout: const Duration(seconds: 3),
      maximumDuration: const Duration(seconds: 20),
    );
    expect(await control.stop(RecordingStopReason.manual), isNull);
    expect(control.state, RecordingState.failed);
    port.failStop = false;
    await control.dispose();
  });
  test('interruption preserves audio for explicit recognition', () async {
    final port = FakeRecorder();
    final control = recorder(port);
    final result = Completer<RecordingResult>();
    control.onCompleted = result.complete;
    await control.start(
      silenceTimeout: const Duration(seconds: 3),
      maximumDuration: const Duration(seconds: 20),
    );
    port.states.add(false);
    final recording = await result.future;
    expect(recording.reason, RecordingStopReason.interrupted);
    expect(await File(recording.path!).exists(), isTrue);
    await control.dispose();
  });
  test(
    'playback stop settles wait even without natural completion event',
    () async {
      final port = FakePlayback();
      final control = PlaybackController(port);
      final playing = control.play('test.wav');
      while (port.plays == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await control.stop();
      expect(
        await playing.timeout(const Duration(seconds: 1)),
        PlaybackOutcome.cancelled,
      );
      expect(port.events.hasListener, isFalse);
      await control.dispose();
    },
  );
  test(
    'playback completion, errors and timeout release subscriptions',
    () async {
      final port = FakePlayback();
      final control = PlaybackController(
        port,
        timeout: const Duration(milliseconds: 20),
      );
      var playing = control.play('test.wav');
      while (port.plays == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      port.events.add(null);
      expect(await playing, PlaybackOutcome.completed);
      expect(await control.play('test.wav'), PlaybackOutcome.failed);
      port.fail = true;
      expect(await control.play('test.wav'), PlaybackOutcome.failed);
      expect(port.events.hasListener, isFalse);
      await control.dispose();
    },
  );
  test(
    'TTS cache separates providers and coalesces identical requests',
    () async {
      final first = FakeTts();
      final second = FakeTts();
      final cache = TtsCache(
        service: first,
        identity: 'provider-a:voice-a',
        directory: () async => root,
      );
      final paths = await Future.wait([
        cache.resolve('你好', '中文'),
        cache.resolve('你好', '中文'),
      ]);
      expect(paths[0], paths[1]);
      expect(first.calls, 1);
      final other = TtsCache(
        service: second,
        identity: 'provider-b:voice-b',
        directory: () async => root,
      );
      expect(await other.resolve('你好', '中文'), isNot(paths[0]));
      expect(second.calls, 1);
    },
  );
}
