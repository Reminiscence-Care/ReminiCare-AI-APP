import '../app_log.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import '../api_services.dart';
import '../remini_care_config.dart';
import 'audio_ports.dart';
import 'recording_controller.dart';
import 'speech_services.dart';
import 'stt_result.dart';
import 'tts_cache.dart';

/// Owns one recorder and player; all microphone/playback requests use this facade.
class VoiceAssistantManager {
  VoiceAssistantManager({
    RecorderPort? recorder,
    PlaybackPort? playback,
    ITTSService? tts,
    Future<String> Function()? createPath,
    Future<void> Function()? activate,
    TtsCache? cache,
  }) {
    _playback = PlaybackController(playback ?? NativePlaybackPort());
    _recording = RecordingController(
      recorder ?? NativeRecorderPort(),
      createPath:
          createPath ??
          () async {
            final root = await getTemporaryDirectory();
            return '${root.path}/reminicare_chat_smart_${DateTime.now().microsecondsSinceEpoch}.wav';
          },
      activate: activate ?? _activate,
    );
    _recording.onWarning = (warning) => onWarning?.call(warning);
    _recording.onState = (state) {
      if (state == RecordingState.failed) onRecordingFailed?.call();
    };
    _recording.onCompleted = (result) {
      if (_disposed) return;
      final paths = result.path == null ? <String>[] : [result.path!];
      if (result.reason == RecordingStopReason.interrupted) {
        onInterrupted?.call(paths);
      } else {
        onSpeechCompleted?.call(paths);
      }
    };
    _cache =
        cache ??
        TtsCache(
          service: tts ?? ApiServices().tts,
          identity: ReminiCareConfig.ttsCacheIdentity,
          directory: getApplicationDocumentsDirectory,
        );
  }

  late final PlaybackController _playback;
  late final RecordingController _recording;
  late final TtsCache _cache;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  AudioSession? _session;
  bool _disposed = false;
  bool _startingRecording = false;
  Future<void>? _closing;
  int _epoch = 0;
  Completer<void>? _playCancellation;
  void Function(String)? onPlayingLanguageChanged;
  void Function(List<String>)? onSpeechCompleted;
  void Function(List<String>)? onInterrupted;
  void Function(String)? onWarning;
  void Function()? onRecordingFailed;
  bool get isListening => _recording.state == RecordingState.recording;
  RecordingState get recordingState => _recording.state;

  Future<void> _activate() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      return;
    }
    final session = _session ??= await AudioSession.instance;
    if (_subscriptions.isEmpty) {
      _subscriptions.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin) unawaited(interrupt());
        }),
      );
      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) => unawaited(interrupt())),
      );
      _subscriptions.add(
        session.devicesChangedEventStream.listen((event) {
          if (isListening &&
              [
                ...event.devicesAdded,
                ...event.devicesRemoved,
              ].any((device) => device.isInput)) {
            unawaited(interrupt());
          }
        }),
      );
    }
    // Applied after plugins are initialized, before each audio operation.
    final playback = _playback.port;
    if (playback is NativePlaybackPort) await playback.configure();
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
    if (!await session.setActive(true)) {
      throw const SttException(
        SttErrorKind.invalidAudio,
        '目前無法取得麥克風或音訊使用權，請稍後重試。',
      );
    }
  }

  Future<bool> startChatFlow({
    Duration silenceTimeout = const Duration(seconds: 6),
    Duration maximumDuration = const Duration(seconds: 180),
  }) async {
    if (_disposed || _startingRecording || isListening) return false;
    _startingRecording = true;
    try {
      final epoch = ++_epoch;
      await stopCurrentPlayback();
      if (_disposed || epoch != _epoch) return false;
      return await _recording.start(
        silenceTimeout: silenceTimeout,
        maximumDuration: maximumDuration,
      );
    } finally {
      _startingRecording = false;
    }
  }

  Future<void> forceEndChat() async {
    await _recording.stop(RecordingStopReason.manual);
  }

  Future<void> stopActiveAudioOperations() async {
    ++_epoch;
    await _recording.stop(RecordingStopReason.cancelled);
  }

  Future<void> interrupt() async {
    ++_epoch;
    await stopCurrentPlayback().catchError((Object _) {});
    await _recording.stop(RecordingStopReason.interrupted);
    try {
      await _session?.setActive(false);
    } catch (_) {
      /* Interruption may already deactivate the session. */
    }
  }

  Future<void> stopCurrentPlayback() async {
    final cancellation = _playCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    await _playback.stop();
  }

  Future<PlaybackOutcome> playLanguageSequence({
    required List<String> texts,
    required List<String> languages,
    int repeatCount = 1,
    int gapMs = 300,
    int partGapMs = 150,
  }) async {
    if (_disposed ||
        _startingRecording ||
        isListening ||
        _recording.state == RecordingState.preparing) {
      return PlaybackOutcome.cancelled;
    }
    await stopCurrentPlayback();
    final cancellation = Completer<void>();
    _playCancellation = cancellation;
    bool getCancelled() => _disposed || cancellation.isCompleted;
    try {
      await _activate();
      for (var repeat = 0; repeat < repeatCount; repeat++) {
        for (final language in languages) {
          for (final text in texts) {
            if (getCancelled()) return PlaybackOutcome.cancelled;
            AppLog.instance.record(
              LogArea.tts,
              LogEvent.started,
              detail: language == '台語' ? 'tw' : 'zh',
            );
            final path = await Future.any<String?>([
              _cache.resolve(text, language),
              cancellation.future.then((_) => null),
            ]);
            if (getCancelled()) return PlaybackOutcome.cancelled;
            if (path == null) {
              AppLog.instance.record(LogArea.tts, LogEvent.failed);
              return PlaybackOutcome.failed;
            }
            onPlayingLanguageChanged?.call(language);
            final playbackWatch = Stopwatch()..start();
            final outcome = await _playback.play(path);
            AppLog.instance.record(
              LogArea.tts,
              outcome == PlaybackOutcome.completed
                  ? LogEvent.completed
                  : outcome == PlaybackOutcome.cancelled
                  ? LogEvent.cancelled
                  : LogEvent.failed,
              durationMs: playbackWatch.elapsedMilliseconds,
              detail: language == '台語' ? 'tw' : 'zh',
            );
            if (outcome != PlaybackOutcome.completed) return outcome;
            if (partGapMs > 0) {
              await Future.any([
                Future<void>.delayed(Duration(milliseconds: partGapMs)),
                cancellation.future,
              ]);
            }
          }
          if (gapMs > 0) {
            await Future.any([
              Future<void>.delayed(Duration(milliseconds: gapMs)),
              cancellation.future,
            ]);
          }
        }
      }
      return getCancelled()
          ? PlaybackOutcome.cancelled
          : PlaybackOutcome.completed;
    } catch (_) {
      return getCancelled()
          ? PlaybackOutcome.cancelled
          : PlaybackOutcome.failed;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    await stopCurrentPlayback().catchError((Object _) {});
    await _recording.dispose().catchError((Object _) {});
    await _playback.dispose().catchError((Object _) {});
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _session?.setActive(false);
    } catch (_) {
      /* OS may already release audio focus. */
    }
  }

  void dispose() {
    unawaited(close().catchError((Object _) {}));
  }
}
