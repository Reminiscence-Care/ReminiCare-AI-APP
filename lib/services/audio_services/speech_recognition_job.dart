import 'dart:async';
import '../app_log.dart';
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
    AppLog.instance.record(LogArea.stt, LogEvent.started, operationId: id);
    SttResult? observed;
    try {
      if (isCancelled) return await _cancelled.future;
      observed = await Future.any<SttResult>([
        run((complete, total) {
          if (!isCancelled && !_progress.isClosed) {
            _progress.add(SpeechProgress(complete, total));
            AppLog.instance.record(
              LogArea.stt,
              LogEvent.progress,
              operationId: id,
              complete: complete,
              total: total,
            );
          }
        }),
        _cancelled.future,
      ]);
      return observed;
    } catch (error) {
      observed = SttResult(
        error: error is SttException
            ? error
            : const SttException(SttErrorKind.network, '語音辨識失敗，請重試。'),
      );
      return observed;
    } finally {
      AppLog.instance.record(
        LogArea.stt,
        isCancelled
            ? LogEvent.cancelled
            : observed?.error != null
            ? LogEvent.failed
            : LogEvent.completed,
        operationId: id,
        durationMs: watch.elapsedMilliseconds,
        detail: observed?.error?.kind.name,
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
