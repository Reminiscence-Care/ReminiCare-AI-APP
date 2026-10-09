import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/services/audio_services/audio_ports.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/audio_services/tts_cache.dart';
import 'package:remini_care_ai_app/services/audio_services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/audio_services/wav_audio.dart';
import 'audio_lifecycle_test.dart' show FakePlayback, FakeRecorder;

class _Tts implements ITTSService {
  final languages = <String>[];
  @override
  Future<Uint8List?> generateSpeech(String text, String language) async {
    languages.add(language);
    return WavAudio(Uint8List(3200)).encode();
  }
}

class _Playback extends FakePlayback {
  _Playback(this.autoComplete);
  final bool autoComplete;
  final started = Completer<void>();
  @override
  Future<void> play(String path) async {
    await super.play(path);
    if (!started.isCompleted) started.complete();
    if (autoComplete) scheduleMicrotask(() => events.add(null));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late VoiceAssistantManager voice;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('reminicare_bilingual_');
  });
  tearDown(() async {
    await voice.close();
    await root.delete(recursive: true);
  });
  VoiceAssistantManager create(_Tts tts, _Playback playback) =>
      voice = VoiceAssistantManager(
        recorder: FakeRecorder(),
        playback: playback,
        tts: tts,
        activate: () async {},
        cache: TtsCache(
          service: tts,
          identity: 'bilingual-test',
          directory: () async => root,
        ),
        createPath: () async => '${root.path}/recording.wav',
      );
  test('real sequence plays Taiwanese then Chinese in order', () async {
    final tts = _Tts();
    final playback = _Playback(true);
    create(tts, playback);
    final result = await voice.playLanguageSequence(
      texts: ['請大家介紹自己'],
      languages: ['台語', '中文'],
      gapMs: 0,
      partGapMs: 0,
    );
    expect(result, PlaybackOutcome.completed);
    expect(tts.languages, ['台語', '中文']);
    expect(playback.plays, 2);
  });
  test('cancel first language does not start Chinese', () async {
    final tts = _Tts();
    final playback = _Playback(false);
    create(tts, playback);
    final playing = voice.playLanguageSequence(
      texts: ['請大家介紹自己'],
      languages: ['台語', '中文'],
      gapMs: 0,
      partGapMs: 0,
    );
    await playback.started.future;
    await voice.stopCurrentPlayback();
    expect(await playing, PlaybackOutcome.cancelled);
    expect(tts.languages, ['台語']);
    expect(playback.plays, 1);
  });
}
