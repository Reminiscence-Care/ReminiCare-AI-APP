import '../app_log.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

abstract interface class CancelableAiWork {
  void cancelPending();
}

/// Each request can release its connection without closing a shared client.
class AiHttpTransport implements CancelableAiWork {
  AiHttpTransport(
    this.client, {
    required this.timeout,
    this.logArea = LogArea.ai,
  });
  final LogArea logArea;
  static int _nextId = 0;
  final http.Client client;
  final Duration timeout;
  final Set<Completer<void>> _active = {};
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('POST', url, headers: headers, body: body);
  Future<http.Response> get(Uri url) => _request('GET', url);
  Future<http.Response> _request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final id = ++_nextId;
    final watch = Stopwatch()..start();
    AppLog.instance.record(logArea, LogEvent.requestStarted, operationId: id);
    final aborted = Completer<void>();
    _active.add(aborted);
    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: aborted.future,
    );
    if (headers != null) request.headers.addAll(headers);
    if (body is String) {
      request.body = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body is Map<String, String>) {
      request.bodyFields = body;
    }
    try {
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            timeout,
            onTimeout: () {
              if (!aborted.isCompleted) aborted.complete();
              throw TimeoutException('AI request timeout');
            },
          );
      AppLog.instance.record(
        logArea,
        LogEvent.requestCompleted,
        operationId: id,
        durationMs: watch.elapsedMilliseconds,
        statusCode: response.statusCode,
        bytes: response.bodyBytes.length,
      );
      return response;
    } catch (error) {
      AppLog.instance.record(
        logArea,
        LogEvent.requestFailed,
        operationId: id,
        durationMs: watch.elapsedMilliseconds,
        detail: error is TimeoutException
            ? 'timeout'
            : error is http.RequestAbortedException
            ? 'cancelled'
            : 'network',
      );
      rethrow;
    } finally {
      _active.remove(aborted);
    }
  }

  @override
  void cancelPending() {
    for (final request in _active) {
      if (!request.isCompleted) request.complete();
    }
  }
}
