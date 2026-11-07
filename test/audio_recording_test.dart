import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remini_care_ai_app/services/app_log.dart';
import 'package:remini_care_ai_app/services/audio_services/wav_audio.dart';
import 'package:remini_care_ai_app/services/audio_services/ncku_segmented_stt.dart';
import 'package:remini_care_ai_app/services/audio_services/stt_result.dart';
import 'package:remini_care_ai_app/services/topic_catalog.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_pause_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reminicare_audio_test_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<String> audioFile(int seconds) async {
    final bytes = Uint8List(WavAudio.bytesPerSecond * seconds);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = i % 251;
    }
    final path = '${root.path}/audio.wav';
    await File(path).writeAsBytes(WavAudio(bytes).encode());
    return path;
  }

  test('WAV splitting preserves every sample and respects duration', () {
    final bytes = Uint8List.fromList(List.generate(800000, (i) => i % 251));
    final parsed = WavAudio.parse(WavAudio(bytes).encode());
    final parts = parsed.split();
    expect(parts.every((s) => s.seconds <= 5), isTrue);
    expect(parts.expand((s) => s.pcm).toList(), bytes);
    expect(() => WavAudio.parse(Uint8List(12)), throwsFormatException);
  });

  for (final seconds in [3, 6]) {
    test('$seconds-second pause requires speech and restarts on voice', () {
      final detector = SpeechPauseDetector(
        silenceTimeout: Duration(seconds: seconds),
      );
      expect(
        detector.sample(elapsed: const Duration(seconds: 4), loud: false),
        isFalse,
      );
      detector.sample(elapsed: const Duration(seconds: 5), loud: true);
      detector.sample(elapsed: const Duration(milliseconds: 5200), loud: true);
      expect(
        detector.sample(
          elapsed: Duration(milliseconds: 5200 + seconds * 1000 - 1),
          loud: false,
        ),
        isFalse,
      );
      detector.sample(
        elapsed: Duration(milliseconds: 5200 + seconds * 1000 - 1),
        loud: true,
      );
      expect(
        detector.sample(
          elapsed: Duration(milliseconds: 5200 + seconds * 2000 - 1),
          loud: false,
        ),
        isTrue,
      );
      final idle = SpeechPauseDetector(
        silenceTimeout: Duration(seconds: seconds),
      );
      expect(
        idle.sample(elapsed: const Duration(seconds: 15), loud: false),
        isTrue,
      );
    });
  }

  test('WAV parser accepts additional chunks', () {
    final encoded = WavAudio(Uint8List(32000)).encode();
    final extra = Uint8List.fromList([74, 85, 78, 75, 2, 0, 0, 0, 1, 2]);
    final combined =
        (BytesBuilder()
              ..add(encoded.sublist(0, 12))
              ..add(extra)
              ..add(encoded.sublist(12)))
            .takeBytes();
    expect(WavAudio.parse(combined).seconds, 1);
  });

  Uint8List windowsRecording(Uint8List pcm) {
    final standard = WavAudio(pcm).encode();
    final bytes = Uint8List(82 + pcm.length);
    bytes.setRange(0, 36, standard);
    final header = ByteData.sublistView(bytes);
    header.setUint32(4, pcm.length + 40, Endian.little);
    header.setUint32(16, 18, Endian.little);
    bytes.setRange(38, 42, 'data'.codeUnits);
    header.setUint32(42, pcm.length, Endian.little);
    bytes.setRange(48, 74, bytes.sublist(12, 38));
    bytes.setRange(74, 82, bytes.sublist(38, 46));
    bytes.setRange(82, bytes.length, pcm);
    return bytes;
  }

  test('Windows rewritten header recovers all PCM without header debris', () {
    final pcm = Uint8List.fromList(List.generate(191298, (i) => i % 251));
    final parsed = WavAudio.parse(windowsRecording(pcm));
    expect(parsed.pcm, pcm);
    expect(WavAudio.parse(parsed.encode()).pcm, pcm);
    expect(parsed.split().expand((s) => s.pcm).toList(), pcm);
  });

  test('Windows recovery rejects truncated or mismatched header layouts', () {
    final bytes = windowsRecording(Uint8List(32000));
    expect(
      () => WavAudio.parse(Uint8List.sublistView(bytes, 0, bytes.length - 2)),
      throwsFormatException,
    );
    bytes[60] = 2; // Duplicated format no longer matches the outer format.
    expect(() => WavAudio.parse(bytes), throwsFormatException);
  });

  Uint8List macOsRecording(Uint8List pcm, {int subFormat = 1}) {
    // Layout observed from record_macos (AVFoundation): JUNK + extensible fmt.
    final builder = BytesBuilder();
    final header = ByteData(104);
    header.setUint32(4, 96 + pcm.length, Endian.little);
    header.setUint32(16, 28, Endian.little);
    header.setUint32(52, 40, Endian.little);
    header.setUint16(56, 0xFFFE, Endian.little);
    header.setUint16(58, 1, Endian.little);
    header.setUint32(60, 16000, Endian.little);
    header.setUint32(64, 32000, Endian.little);
    header.setUint16(68, 2, Endian.little);
    header.setUint16(70, 16, Endian.little);
    header.setUint16(72, 22, Endian.little);
    header.setUint16(74, 16, Endian.little);
    header.setUint32(76, 4, Endian.little);
    header.setUint32(100, pcm.length, Endian.little);
    final bytes = header.buffer.asUint8List();
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    bytes.setRange(8, 16, 'WAVEJUNK'.codeUnits);
    bytes.setRange(48, 52, 'fmt '.codeUnits);
    bytes.setRange(80, 96, [
      subFormat, 0, 0, 0, 0, 0, 0x10, 0, //
      0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71,
    ]);
    bytes.setRange(96, 100, 'data'.codeUnits);
    builder
      ..add(bytes)
      ..add(pcm);
    return builder.takeBytes();
  }

  test('macOS extensible PCM header parses; non-PCM sub-format rejected', () {
    final pcm = Uint8List.fromList(List.generate(32000, (i) => i % 251));
    expect(WavAudio.parse(macOsRecording(pcm)).pcm, pcm);
    expect(
      () => WavAudio.parse(macOsRecording(pcm, subFormat: 3)),
      throwsFormatException,
    );
  });

  final retainedSample = Platform.environment['REMINICARE_WAV_SAMPLE'];
  if (retainedSample != null) {
    test(
      'retained device recording parses and reaches segmented STT',
      () async {
        final bytes = await File(retainedSample).readAsBytes();
        final audio = WavAudio.parse(bytes);
        expect(audio.pcm, bytes.sublist(82));
        var requests = 0;
        var sentPcmBytes = 0;
        final service = NckuSegmentedStt(
          token: () => 'test-token',
          client: MockClient((request) async {
            requests++;
            expect(
              request.bodyBytes.length,
              lessThanOrEqualTo(NckuSegmentedStt.maximumBodyBytes),
            );
            final form = Uri.splitQueryString(request.body);
            sentPcmBytes += WavAudio.parse(
              base64Decode(form['audio']!),
            ).pcm.length;
            return http.Response('{"sentence":"sample"}', 200);
          }),
        );
        await service.transcribe(retainedSample);
        expect(requests, greaterThanOrEqualTo(audio.split().length));
        expect(sentPcmBytes, audio.pcm.length);
      },
    );
  }

  test(
    'long audio stays below encoded budget with <=2 concurrent requests',
    () async {
      var active = 0;
      var peak = 0;
      var index = 0;
      final service = NckuSegmentedStt(
        token: () => 'test-token',
        client: MockClient((request) async {
          final current = index++;
          active++;
          if (active > peak) peak = active;
          expect(
            utf8.encode(request.body).length,
            lessThanOrEqualTo(240 * 1024),
          );
          await Future<void>.delayed(
            Duration(milliseconds: current.isEven ? 8 : 1),
          );
          active--;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'sentence': '段$current'})),
            200,
          );
        }),
      );
      final result = await service.transcribe(await audioFile(18));
      expect(result!.split('，'), List.generate(index, (i) => '段$i'));
      expect(peak, lessThanOrEqualTo(2));
    },
  );

  test('retry resends only failed audio segments', () async {
    final counts = <String, int>{};
    var fail = true;
    var position = 0;
    final service = NckuSegmentedStt(
      token: () => 'test-token',
      client: MockClient((request) async {
        counts.update(request.body, (v) => v + 1, ifAbsent: () => 1);
        final current = position++;
        if (fail && current == 1) return http.Response('{}', 503);
        return http.Response('{"sentence":"ok"}', 200);
      }),
    );
    final path = await audioFile(12);
    await expectLater(service.transcribe(path), throwsA(isA<SttException>()));
    final firstRequests = position;
    fail = false;
    expect(await service.transcribe(path), isNotEmpty);
    expect(position, firstRequests + 1);
  });

  test('nested 413 splits until accepted and retains the full audio', () async {
    var acceptedBytes = 0;
    final service = NckuSegmentedStt(
      token: () => 'test-token',
      client: MockClient((request) async {
        final form = Uri.splitQueryString(request.body);
        final audio = WavAudio.parse(base64Decode(form['audio']!));
        if (audio.seconds > 1.5) {
          return http.Response('{"error":"413 Request Entity Too Large"}', 500);
        }
        acceptedBytes += audio.pcm.length;
        return http.Response('{"sentence":"ok"}', 200);
      }),
    );
    expect(await service.transcribe(await audioFile(5)), isNotEmpty);
    expect(acceptedBytes, 160000);
  });

  test('timeout is distinct from silence', () async {
    final service = NckuSegmentedStt(
      token: () => 'test-token',
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 15));
        return http.Response('{"sentence":"<{silent}>"}', 200);
      }),
    );
    await expectLater(
      service.transcribe(await audioFile(1)),
      throwsA(
        isA<SttException>().having((e) => e.kind, 'kind', SttErrorKind.timeout),
      ),
    );
  });

  test('proxy 500 bodies are classified without logging their text', () {
    const refused =
        '{"error": "An error occurred: HTTPConnectionPool(host=\'140.116.245.154\', '
        'port=9001): Max retries exceeded (Caused by NewConnectionError(\'...: '
        'Failed to establish a new connection: [Errno 111] Connection refused\'))"}';
    expect(nckuSttErrorDetail(500, refused), 'sttBackendRefused');
    expect(
      nckuSttErrorDetail(500, '{"error":"Read timed out. (read timeout=30)"}'),
      'sttBackendTimeout',
    );
    expect(nckuSttErrorDetail(500, '{"error":"boom"}'), 'sttBackendError');
    expect(nckuSttErrorDetail(502, '<html>Bad Gateway</html>'), 'server');
    expect(nckuSttErrorDetail(403, ''), 'authentication');
  });

  test(
    'backend refused surfaces a server-side message and log entry',
    () async {
      final log = AppLog.instance..clear();
      final service = NckuSegmentedStt(
        token: () => 'test-token',
        client: MockClient(
          (_) async => http.Response(
            '{"error":"NewConnectionError: Connection refused"}',
            500,
          ),
        ),
      );
      await expectLater(
        service.transcribe(await audioFile(1)),
        throwsA(
          isA<SttException>()
              .having((e) => e.kind, 'kind', SttErrorKind.server)
              .having((e) => e.message, 'message', contains('伺服器端問題')),
        ),
      );
      final failures = log.entries.where(
        (e) => e.event == LogEvent.requestFailed,
      );
      expect(failures.single.detail, 'sttBackendRefused');
      expect(failures.single.statusCode, 500);
      expect(log.exportText(), isNot(contains('Connection refused')));
    },
  );

  test(
    'catalog has twelve distinct paired assets and avoids previous round',
    () async {
      final catalog = await TopicCatalog.load();
      expect(catalog.topics.length, greaterThanOrEqualTo(12));
      expect(
        catalog.topics.map((t) => t.topicId).toSet().length,
        catalog.topics.length,
      );
      final first = catalog.pickFour();
      final second = catalog.pickFour(
        excluding: first.map((t) => t.topicId).toSet(),
      );
      expect(
        first
            .map((t) => t.topicId)
            .toSet()
            .intersection(second.map((t) => t.topicId).toSet()),
        isEmpty,
      );
      for (final topic in catalog.topics) {
        expect(await File(topic.thumbnailPath!.substring(6)).exists(), isTrue);
        expect(
          topic.thumbnailAttribution!.originalUrl,
          startsWith('https://commons.wikimedia.org/'),
        );
      }
    },
  );
}
