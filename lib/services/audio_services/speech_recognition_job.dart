import 'dart:async';
import 'package:flutter/foundation.dart';
import 'stt_result.dart';

class SpeechProgress {
  const SpeechProgress(this.complete, this.total);
  final int complete;
  final int total;
}

/// Cancellation ends observation promptly; adapters release their own resources.
class SpeechRecognitionJob {
  SpeechRecognitionJob({required this.run, required this.abort});
  final Future<SttResult> Function(void Function(int, int) progress) run;
  final void Function() abort;
  static int _nextId = 0;
  final int id = ++_nextId;
  final _progress = StreamController<SpeechProgress>.broadcast();
  final _cancelled = Completer<SttResult>();
  Future<SttResult>? _result;
  bool get isCancelled => _cancelled.isCompleted;
  Stream<SpeechProgress> get progress => _progress.stream;
  Future<SttResult> get result => _result ??= _start();
  Future<SttResult> _start() async {
    final watch = Stopwatch()..start();
    try {
      if (isCancelled) return await _cancelled.future;
      return await Future.any([
        run((complete, total) {
          if (!isCancelled && !_progress.isClosed) {
            _progress.add(SpeechProgress(complete, total));
          }
        }),
        _cancelled.future,
      ]);
    } catch (error) {
      return SttResult(
        error: error is SttException
            ? error
            : const SttException(SttErrorKind.network, '語音辨識失敗，請重試。'),
      );
    } finally {
      debugPrint(
        '[STT] job=$id elapsedMs=${watch.elapsedMilliseconds} cancelled=$isCancelled',
      );
      await _progress.close();
    }
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete(
      const SttResult(error: SttException(SttErrorKind.cancelled, '已取消辨識。')),
    );
    abort();
    if (_result == null) unawaited(_progress.close());
  }
}

abstract interface class JobSttService {
  SpeechRecognitionJob createJob(String path);
}
