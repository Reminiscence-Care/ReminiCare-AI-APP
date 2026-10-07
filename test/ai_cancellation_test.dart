import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remini_care_ai_app/services/ai/ai_http_transport.dart';

class AbortAwareClient extends http.BaseClient {
  final List<Completer<http.StreamedResponse>> requests = [];
  int aborted = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final result = Completer<http.StreamedResponse>();
    requests.add(result);
    final abort = (request as http.AbortableRequest).abortTrigger!;
    return Future.any([
      result.future,
      abort.then<http.StreamedResponse>((_) {
        aborted++;
        throw StateError('cancelled request');
      }),
    ]);
  }
}

void main() {
  test(
    'AI cancellation aborts outstanding request without breaking the next one',
    () async {
      final client = AbortAwareClient();
      final transport = AiHttpTransport(
        client,
        timeout: const Duration(seconds: 1),
      );
      final pending = transport.post(
        Uri.parse('https://example.test'),
        body: '{}',
      );
      transport.cancelPending();
      await expectLater(pending, throwsA(isA<StateError>()));
      expect(client.aborted, 1);
      final next = transport.post(
        Uri.parse('https://example.test'),
        body: '{}',
      );
      client.requests.last.complete(
        http.StreamedResponse(Stream.value([123, 125]), 200),
      );
      expect((await next).body, '{}');
    },
  );
  test(
    'AI timeout releases underlying request instead of leaving a connection running',
    () async {
      final client = AbortAwareClient();
      final transport = AiHttpTransport(
        client,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        transport.get(Uri.parse('https://example.test')),
        throwsA(isA<TimeoutException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.aborted, 1);
    },
  );
}
