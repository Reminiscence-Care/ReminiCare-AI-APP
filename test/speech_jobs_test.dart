import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remini_care_ai_app/services/audio_services/ncku_segmented_stt.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/audio_services/stt_result.dart';
import 'package:remini_care_ai_app/services/audio_services/wav_audio.dart';

class FakeChannel implements YatingChannel {
  FakeChannel({
    this.eof = true,
    this.malformed = false,
    this.delay = Duration.zero,
  }) {
    events = StreamController<dynamic>(
      onListen: () {
        scheduleMicrotask(() => events.add('{"status":"ok"}'));
      },
    );
  }
  late final StreamController<dynamic> events;
  final bool eof;
  final bool malformed;
  final Duration delay;
  Timer? timer;
  bool closed = false;
  @override
  Stream<dynamic> get messages => events.stream;
  @override
  void send(dynamic value) {
    if (value is Uint8List && value.isEmpty) {
      if (malformed) {
        events.add('not JSON');
        return;
      }
      events.add('{"pipe":{"asr_sentence":"partial"}}');
      if (eof) {
        timer = Timer(
          delay,
          () => events.add(
            '{"pipe":{"asr_sentence":"complete","asr_state":"asr_eof"}}',
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    timer?.cancel();
    await events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String path;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reminicare_speech_job_');
    path = '${root.path}/audio.wav';
    await File(path).writeAsBytes(WavAudio(Uint8List(32000)).encode());
  });
  tearDown(() => root.delete(recursive: true));

  test('cancelled NCKU job never sends remaining segments', () async {
    await File(path).writeAsBytes(WavAudio(Uint8List(32000 * 18)).encode());
    final gates = <Completer<http.Response>>[];
    final service = NckuSegmentedStt(
      token: () => 'test',
      clientFactory: () => MockClient((_) {
        final gate = Completer<http.Response>();
        gates.add(gate);
        return gate.future;
      }),
    );
    final job = service.createJob(path);
    final future = job.result;
    while (gates.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    job.cancel();
    expect((await future).error?.kind, SttErrorKind.cancelled);
    for (final gate in gates) {
      gate.complete(http.Response('{"sentence":"sample"}', 200));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gates.length, 2);
    service.forget(path);
  });
  test(
    'NCKU job retries only failed segments with isolated progress',
    () async {
      await File(path).writeAsBytes(
        WavAudio(
          Uint8List.fromList(List.generate(32000 * 12, (i) => i % 251)),
        ).encode(),
      );
      var calls = 0;
      var fail = true;
      final service = NckuSegmentedStt(
        token: () => 'test',
        clientFactory: () => MockClient((_) async {
          final position = calls++;
          return fail && position == 1
              ? http.Response('{}', 503)
              : http.Response('{"sentence":"sample"}', 200);
        }),
      );
      expect(
        (await service.createJob(path).result).error?.kind,
        SttErrorKind.server,
      );
      final firstCalls = calls;
      fail = false;
      final retry = service.createJob(path);
      final progress = <int>[];
      final subscription = retry.progress.listen(
        (p) => progress.add(p.complete),
      );
      expect((await retry.result).error, isNull);
      expect(calls, firstCalls + 1);
      expect(progress.last, 3);
      await subscription.cancel();
      service.forget(path);
    },
  );
  YatingSttService yating(
    FakeChannel channel, {
    Duration timeout = const Duration(seconds: 1),
  }) => YatingSttService(
    client: MockClient(
      (_) async => http.Response('{"success":true,"auth_token":"test"}', 201),
    ),
    connect: (_) async => channel,
    completionTimeout: timeout,
    sendDelay: Duration.zero,
  );

  test(
    'Yating waits for delayed EOF instead of accepting partial text',
    () async {
      final channel = FakeChannel(delay: const Duration(milliseconds: 80));
      expect(await yating(channel).transcribe(path), 'complete');
      expect(channel.closed, isTrue);
    },
  );
  test(
    'Yating completion deadline preserves partial result as an error',
    () async {
      final channel = FakeChannel(eof: false);
      await expectLater(
        yating(
          channel,
          timeout: const Duration(milliseconds: 30),
        ).transcribe(path),
        throwsA(
          isA<SttException>()
              .having((e) => e.kind, 'kind', SttErrorKind.incomplete)
              .having((e) => e.partialText, 'partial', 'partial'),
        ),
      );
      expect(channel.closed, isTrue);
    },
  );
  test(
    'malformed Yating events fail without unhandled async exceptions',
    () async {
      final channel = FakeChannel(malformed: true);
      await expectLater(
        yating(channel).transcribe(path),
        throwsA(
          isA<SttException>().having(
            (e) => e.kind,
            'kind',
            SttErrorKind.invalidResponse,
          ),
        ),
      );
      expect(channel.closed, isTrue);
    },
  );
  test(
    'Yating cancellation closes socket and cannot return partial success',
    () async {
      final channel = FakeChannel(eof: false);
      final service = yating(channel);
      final future = service.transcribe(path);
      while (!channel.events.hasListener) {
        await Future<void>.delayed(Duration.zero);
      }
      service.cancel();
      await expectLater(future, throwsA(isA<SttException>()));
      expect(channel.closed, isTrue);
    },
  );
}
