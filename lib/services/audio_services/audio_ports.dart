import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

abstract interface class RecorderPort {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
  Future<double> amplitude();
  Stream<bool> get recording;
  Future<void> dispose();
}

class NativeRecorderPort implements RecorderPort {
  final AudioRecorder _recorder = AudioRecorder();
  @override
  Future<bool> hasPermission() => _recorder.hasPermission();
  @override
  Future<void> start(String path) async {
    if (Platform.isIOS) await _recorder.ios?.manageAudioSession(false);
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<String?> stop() => _recorder.stop();
  @override
  Future<double> amplitude() async => (await _recorder.getAmplitude()).current;
  @override
  Stream<bool> get recording =>
      _recorder.onStateChanged().map((state) => state == RecordState.record);
  @override
  Future<void> dispose() => _recorder.dispose();
}

abstract interface class PlaybackPort {
  Stream<void> get completed;
  Future<void> play(String path);
  Future<void> stop();
  Future<void> dispose();
}

class NativePlaybackPort implements PlaybackPort {
  final AudioPlayer _player = AudioPlayer();
  Future<void> configure() async {
    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.allowBluetooth,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  @override
  Stream<void> get completed => _player.onPlayerComplete;
  @override
  Future<void> play(String path) => _player.play(DeviceFileSource(path));
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

enum PlaybackOutcome { completed, cancelled, failed }

class PlaybackController {
  PlaybackController(this.port, {this.timeout = const Duration(minutes: 2)});
  final PlaybackPort port;
  final Duration timeout;
  Completer<PlaybackOutcome>? _pending;
  int _epoch = 0;
  Future<void> _hardware = Future.value();
  bool _disposed = false;

  Future<void> _command(Future<void> Function() action) {
    final work = _hardware.then((_) => action());
    _hardware = work.catchError((Object _) {});
    return work;
  }

  Future<void> stop() async {
    _epoch++;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(PlaybackOutcome.cancelled);
    }
    await _command(() => port.stop().timeout(const Duration(seconds: 5)));
  }

  Future<PlaybackOutcome> play(String path) async {
    if (_disposed) return PlaybackOutcome.cancelled;
    await stop();
    if (_disposed) return PlaybackOutcome.cancelled;
    final epoch = ++_epoch;
    final pending = Completer<PlaybackOutcome>();
    _pending = pending;
    final subscription = port.completed.listen(
      (_) {
        if (epoch == _epoch && !pending.isCompleted) {
          pending.complete(PlaybackOutcome.completed);
        }
      },
      onError: (Object _) {
        if (!pending.isCompleted) pending.complete(PlaybackOutcome.failed);
      },
    );
    try {
      await _command(() async {
        if (epoch == _epoch && !_disposed) {
          await port.play(path).timeout(const Duration(seconds: 10));
        }
      });
      return await pending.future.timeout(
        timeout,
        onTimeout: () => PlaybackOutcome.failed,
      );
    } catch (_) {
      return PlaybackOutcome.failed;
    } finally {
      await subscription.cancel();
      if (identical(_pending, pending)) {
        _pending = null;
        await _command(() async {
          if (epoch == _epoch) {
            await port.stop().timeout(const Duration(seconds: 5));
          }
        }).catchError((Object _) {});
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop().catchError((Object _) {});
    await port.dispose();
  }
}
