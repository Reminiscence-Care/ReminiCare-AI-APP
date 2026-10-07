import 'dart:async';
import 'package:http/http.dart' as http;

abstract interface class CancelableAiWork {
  void cancelPending();
}

/// Each request can release its connection without closing a shared client.
class AiHttpTransport implements CancelableAiWork {
  AiHttpTransport(this.client, {required this.timeout});
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
      return await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            timeout,
            onTimeout: () {
              if (!aborted.isCompleted) aborted.complete();
              throw TimeoutException('AI request timeout');
            },
          );
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
