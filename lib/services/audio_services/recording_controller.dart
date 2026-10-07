import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'audio_ports.dart';
import 'speech_pause_detector.dart';
import 'stt_result.dart';

enum RecordingState { idle, preparing, recording, stopping, completed, failed }

enum RecordingStopReason {
  manual,
  silence,
  idle,
  maximumDuration,
  interrupted,
  cancelled,
}

class RecordingResult {
  const RecordingResult(this.path, this.reason, this.duration);
  final String? path;
  final RecordingStopReason reason;
  final Duration duration;
}

class RecordingController {
  RecordingController(
    this.port, {
    required this.createPath,
    required this.activate,
    this.sampleInterval = const Duration(milliseconds: 200),
  });
  final RecorderPort port;
  final Future<String> Function() createPath;
  final Future<void> Function() activate;
  final Duration sampleInterval;
  RecordingState state = RecordingState.idle;
  void Function(RecordingState)? onState;
  void Function(String)? onWarning;
  void Function(RecordingResult)? onCompleted;
  Timer? _timer;
  StreamSubscription<bool>? _subscription;
  Stopwatch _clock = Stopwatch();
  String? _path;
  int _epoch = 0;
  bool _disposed = false;
  bool _sampling = false;
  int _sampleFailures = 0;
  double thresholdDb = -35;
  Future<void> _hardware = Future.value();
  Future<RecordingResult?>? _stopping;

  Future<T> _command<T>(Future<T> Function() command) {
    final work = _hardware.then((_) => command());
    _hardware = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  void _state(RecordingState value) {
    state = value;
    onState?.call(value);
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  Future<bool> start({
    required Duration silenceTimeout,
    required Duration maximumDuration,
  }) async {
    if (_disposed ||
        state == RecordingState.preparing ||
        state == RecordingState.recording ||
        state == RecordingState.stopping) {
      return false;
    }
    final epoch = ++_epoch;
    _state(RecordingState.preparing);
    return _command(() async {
      try {
        if (!await port.hasPermission().timeout(const Duration(seconds: 10))) {
          throw const SttException(
            SttErrorKind.invalidAudio,
            '麥克風權限未開啟，請到裝置設定允許錄音。',
          );
        }
        if (!_current(epoch)) return false;
        await activate();
        if (!_current(epoch)) return false;
        _path = await createPath();
        if (!_current(epoch)) return false;
        await port.start(_path!).timeout(const Duration(seconds: 10));
        if (!_current(epoch)) return false; // queued stop owns finalization
        _clock = Stopwatch()..start();
        _state(RecordingState.recording);
        _sampleFailures = 0;
        _sampling = false;
        thresholdDb = -35;
        var calibrated = false;
        final noise = <double>[];
        final pause = SpeechPauseDetector(silenceTimeout: silenceTimeout);
        await _subscription?.cancel();
        _subscription = port.recording.listen(
          (recording) {
            if (!recording &&
                _current(epoch) &&
                state == RecordingState.recording) {
              unawaited(stop(RecordingStopReason.interrupted));
            }
          },
          onError: (Object _) {
            if (_current(epoch)) {
              unawaited(stop(RecordingStopReason.interrupted));
            }
          },
        );
        _timer = Timer.periodic(sampleInterval, (_) async {
          if (!_current(epoch) || state != RecordingState.recording) return;
          if (_clock.elapsed >= maximumDuration) {
            unawaited(stop(RecordingStopReason.maximumDuration));
            return;
          }
          if (_sampling || _sampleFailures >= 3) return;
          _sampling = true;
          try {
            final db = await port.amplitude().timeout(
              const Duration(seconds: 1),
            );
            if (!_current(epoch) || state != RecordingState.recording) return;
            if (!db.isFinite) throw const FormatException('Invalid amplitude');
            _sampleFailures = 0;
            // Speech participates in detection immediately, not in the noise floor.
            if (!calibrated) {
              if (db > -100 && db < -35) noise.add(db);
              if (_clock.elapsed >= const Duration(seconds: 1)) {
                if (noise.length >= 3) {
                  noise.sort();
                  thresholdDb = (noise[noise.length ~/ 4] + 10).clamp(-45, -35);
                }
                calibrated = true;
              }
            }
            if (pause.sample(
              elapsed: _clock.elapsed,
              loud: db >= thresholdDb,
            )) {
              unawaited(
                stop(
                  pause.hasSpoken
                      ? RecordingStopReason.silence
                      : RecordingStopReason.idle,
                ),
              );
            }
          } catch (_) {
            if (_current(epoch) && ++_sampleFailures >= 3) {
              onWarning?.call('自動停頓偵測暫時無法使用，請說完後按「說完了」。');
            }
          } finally {
            _sampling = false;
          }
        });
        return true;
      } catch (error) {
        if (_current(epoch)) _state(RecordingState.failed);
        // A failed start can still leave native hardware running.
        try {
          await port.stop().timeout(const Duration(seconds: 5));
        } catch (_) {}
        rethrow;
      }
    });
  }

  Future<RecordingResult?> stop(RecordingStopReason reason) {
    if (state == RecordingState.stopping) {
      return _stopping ?? Future.value(null);
    }
    if (state == RecordingState.idle ||
        state == RecordingState.completed ||
        _disposed) {
      return Future.value(null);
    }
    ++_epoch;
    _timer?.cancel();
    _clock.stop();
    _state(RecordingState.stopping);
    return _stopping = _command(() async {
      await _subscription?.cancel();
      _subscription = null;
      String? path;
      try {
        path = await port.stop().timeout(const Duration(seconds: 5)) ?? _path;
      } catch (_) {
        _state(RecordingState.failed);
        onWarning?.call('停止錄音失敗，請重新錄音。');
        return null;
      }
      _path = null;
      if (path != null && !await File(path).exists()) path = null;
      final result = RecordingResult(path, reason, _clock.elapsed);
      debugPrint(
        '[Recording] operation=$_epoch durationMs=${result.duration.inMilliseconds} reason=${reason.name} threshold=$thresholdDb',
      );
      _state(RecordingState.completed);
      if (reason == RecordingStopReason.cancelled) {
        if (path != null) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      } else {
        onCompleted?.call(result);
      }
      return result;
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop(RecordingStopReason.cancelled);
    _disposed = true;
    ++_epoch;
    _timer?.cancel();
    await _subscription?.cancel();
    await _hardware;
    await port.dispose();
  }
}
