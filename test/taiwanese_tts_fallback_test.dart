import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remini_care_ai_app/services/ai/ai_models.dart';
import 'package:remini_care_ai_app/services/ai/llm_client.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/audio_services/taiwanese_tts_fallback.dart';

/// 模擬 9998：讀到 EOT 後回 JSON；預設拒收含漢字的台語。
class _FakeVitsServer {
  _FakeVitsServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeVitsServer> start() async => _FakeVitsServer._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final ServerSocket _server;
  final requests = <List<String>>[];
  bool acceptHanziTaiwanese = false;
  int get port => _server.port;

  void _handle(Socket socket) {
    final buffer = <int>[];
    late StreamSubscription<Uint8List> sub;
    sub = socket.listen((chunk) async {
      buffer.addAll(chunk);
      final text = utf8.decode(buffer, allowMalformed: true);
      if (!text.endsWith('EOT')) return;
      await sub.cancel();
      final parts = text.substring(0, text.length - 3).split('@@@');
      requests.add(parts);
      final lang = parts[2];
      final body = parts[4];
      final ok = lang != 'tw' || acceptHanziTaiwanese || !containsHan(body);
      socket.add(
        utf8.encode(
          jsonEncode(
            ok
                ? {
                    'status': true,
                    'bytes': base64Encode(utf8.encode('WAV:$lang:$body')),
                  }
                : {
                    'status': false,
                    'message': 'Exception occurred during synthesis.',
                  },
          ),
        ),
      );
      await socket.flush();
      await socket.close();
    });
  }

  Future<void> close() => _server.close();
}

class _FakeConverter implements TaiLoConverter {
  _FakeConverter(this.result);
  final String? result;
  final calls = <String>[];
  @override
  Future<String?> toTaiLo(String text, {Duration? timeout}) async {
    calls.add(text);
    return result;
  }
}

class _FakeLegacy implements LegacyTaiwaneseTts {
  final calls = <String>[];
  @override
  Future<Uint8List?> synthesize(String text, {Duration? timeout}) async {
    calls.add(text);
    return Uint8List.fromList(utf8.encode('LEGACY:$text'));
  }
}

class _FakeLlm implements LlmClient {
  _FakeLlm(this.reply);
  final String reply;
  List<LlmMessage>? lastMessages;
  @override
  Future<String> complete({
    required List<LlmMessage> messages,
    double temperature = 0.6,
    int maxTokens = 500,
    bool jsonObject = false,
  }) async {
    lastMessages = messages;
    return reply;
  }
}

String _decode(Uint8List? audio) => audio == null ? 'null' : utf8.decode(audio);

void main() {
  tailoModelTests();
  late _FakeVitsServer server;
  setUp(() async => server = await _FakeVitsServer.start());
  tearDown(() => server.close());

  NckuSpeechService service({
    TaiLoConverter? converter,
    LegacyTaiwaneseTts? legacy,
    TaiwaneseTtsFallback mode = TaiwaneseTtsFallback.llmThenLegacy,
    int? port,
  }) => NckuSpeechService(
    taiLoConverter: converter,
    legacyTaiwanese: legacy,
    taiwaneseFallback: mode,
    ttsHost: InternetAddress.loopbackIPv4.address,
    ttsPort: port ?? server.port,
    ttsTls: false,
    ttsToken: () => 'test-token',
  );

  test('9998 accepts hanzi directly: no fallback is used', () async {
    server.acceptHanziTaiwanese = true;
    final converter = _FakeConverter('lí hó');
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: converter,
      legacy: legacy,
    ).generateSpeech('你好', '台語');
    expect(_decode(audio), 'WAV:tw:你好');
    expect(converter.calls, isEmpty);
    expect(legacy.calls, isEmpty);
    expect(server.requests.single, ['10012', 'test-token', 'tw', 'M04', '你好']);
  });

  test('hanzi rejected: converts to Tâi-lô and retries 9998', () async {
    final converter = _FakeConverter('lí hó');
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: converter,
      legacy: legacy,
    ).generateSpeech('你好', '台語');
    expect(_decode(audio), 'WAV:tw:lí hó');
    expect(converter.calls, ['你好']);
    expect(legacy.calls, isEmpty);
    expect(server.requests.map((r) => r[4]), ['你好', 'lí hó']);
  });

  test('conversion fails: falls back to the legacy server', () async {
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: _FakeConverter(null),
      legacy: legacy,
    ).generateSpeech('你好', '台語');
    expect(_decode(audio), 'LEGACY:你好');
    expect(legacy.calls, ['你好']);
  });

  test('no LLM configured: goes straight to the legacy server', () async {
    final legacy = _FakeLegacy();
    final audio = await service(legacy: legacy).generateSpeech('你好', '台語');
    expect(_decode(audio), 'LEGACY:你好');
  });

  test('llmOnly mode never calls the legacy server', () async {
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: _FakeConverter(null),
      legacy: legacy,
      mode: TaiwaneseTtsFallback.llmOnly,
    ).generateSpeech('你好', '台語');
    expect(audio, isNull);
    expect(legacy.calls, isEmpty);
  });

  test('legacyOnly mode skips the LLM', () async {
    final converter = _FakeConverter('lí hó');
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: converter,
      legacy: legacy,
      mode: TaiwaneseTtsFallback.legacyOnly,
    ).generateSpeech('你好', '台語');
    expect(_decode(audio), 'LEGACY:你好');
    expect(converter.calls, isEmpty);
  });

  test('off mode returns null after the direct failure', () async {
    final converter = _FakeConverter('lí hó');
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: converter,
      legacy: legacy,
      mode: TaiwaneseTtsFallback.off,
    ).generateSpeech('你好', '台語');
    expect(audio, isNull);
    expect(converter.calls, isEmpty);
    expect(legacy.calls, isEmpty);
  });

  test('9998 unreachable: skips the LLM and uses the legacy server', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final converter = _FakeConverter('lí hó');
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: converter,
      legacy: legacy,
      port: port,
    ).generateSpeech('你好', '台語');
    expect(_decode(audio), 'LEGACY:你好');
    expect(converter.calls, isEmpty);
  });

  test('remembers the hanzi rejection and skips the direct attempt', () async {
    final tts = service(converter: _FakeConverter('lí hó'));
    await tts.generateSpeech('你好', '台語');
    await tts.generateSpeech('食飽未', '台語');
    expect(server.requests.map((r) => r[4]), ['你好', 'lí hó', 'lí hó']);
  });

  test('Mandarin path is unchanged and never falls back', () async {
    final converter = _FakeConverter('lí hó');
    final legacy = _FakeLegacy();
    final audio = await service(
      converter: converter,
      legacy: legacy,
    ).generateSpeech('你好', '中文');
    expect(_decode(audio), 'WAV:zh:你好');
    expect(server.requests.single.sublist(2, 4), ['zh', '4793']);
    expect(converter.calls, isEmpty);
    expect(legacy.calls, isEmpty);
  });

  test('normalizeTaiLo keeps romanization and rejects hanzi', () {
    expect(normalizeTaiLo(' Lí hó，guá  sī A-bîng。 '), 'Lí hó, guá sī A-bîng.');
    expect(normalizeTaiLo('lí 好'), isNull);
    expect(normalizeTaiLo(''), isNull);
    expect(normalizeTaiLo('a@@@b'), isNull);
    expect(normalizeTaiLo(42), isNull);
  });

  test('LlmTaiLoConverter parses the JSON reply', () async {
    final llm = _FakeLlm(
      '```json\n{"tailo":"Lí kin-á-ji̍t tsia̍h-pá buē？"}\n```',
    );
    final tailo = await LlmTaiLoConverter(llm).toTaiLo('你今天吃飽了嗎？');
    expect(tailo, 'Lí kin-á-ji̍t tsia̍h-pá buē?');
    expect(llm.lastMessages!.last.content, contains('"你今天吃飽了嗎？"'));
    expect(
      await LlmTaiLoConverter(_FakeLlm('{"tailo":"你好"}')).toTaiLo('你好'),
      isNull,
    );
  });

  test('NckuLegacyTaiwaneseTts speaks the length-prefixed protocol', () async {
    final legacyServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final received = Completer<String>();
    legacyServer.listen((socket) {
      final buffer = <int>[];
      socket.listen((chunk) async {
        buffer.addAll(chunk);
        if (buffer.length < 4) return;
        final length = ByteData.sublistView(
          Uint8List.fromList(buffer.sublist(0, 4)),
        ).getUint32(0);
        if (buffer.length < 4 + length) return;
        received.complete(utf8.decode(buffer.sublist(4, 4 + length)));
        socket.add([...ascii.encode('RIFF'), ...List.filled(60, 0)]);
        await socket.close();
      });
    });
    final client = NckuLegacyTaiwaneseTts(
      token: () => 'test-token',
      host: InternetAddress.loopbackIPv4.address,
      port: legacyServer.port,
    );
    final audio = await client.synthesize('晚上散步');
    expect(await received.future, 'test-token@@@晚上散步@@@M04@@@taiwanese');
    expect(audio!.length, 64);
    expect(ascii.decode(audio.sublist(0, 4)), 'RIFF');
    await legacyServer.close();
  });

  test('fallback mode parsing defaults to LLM then legacy', () {
    expect(
      TaiwaneseTtsFallback.parse(null),
      TaiwaneseTtsFallback.llmThenLegacy,
    );
    expect(
      TaiwaneseTtsFallback.parse('bogus'),
      TaiwaneseTtsFallback.llmThenLegacy,
    );
    expect(
      TaiwaneseTtsFallback.parse('legacy'),
      TaiwaneseTtsFallback.legacyOnly,
    );
    expect(TaiwaneseTtsFallback.parse('off'), TaiwaneseTtsFallback.off);
  });
}

void tailoModelTests() {
  const current = LlmProviderConfig(
    id: 'nvidia',
    displayName: 'NVIDIA',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    model: 'deepseek-ai/deepseek-v4.1-flash',
    apiKeyReference: 'NVIDIA_API_KEY',
  );

  test('Tâi-lô model defaults to OpenAI gpt-4.1 with its own timeout', () {
    final config = TaiLoModelSettings.resolve(
      provider: null,
      model: '',
      current: current,
    );
    expect(config.id, 'openai');
    expect(config.model, 'gpt-4.1');
    expect(config.apiKeyReference, 'OPENAI_API_KEY');
    expect(config.timeout, TaiLoModelSettings.timeout);
  });

  test('Tâi-lô model can follow the chat LLM or use a custom model', () {
    final follow = TaiLoModelSettings.resolve(
      provider: 'current',
      model: ' ',
      current: current,
    );
    expect(follow.model, 'deepseek-ai/deepseek-v4.1-flash');
    expect(follow.apiKeyReference, 'NVIDIA_API_KEY');
    expect(follow.timeout, TaiLoModelSettings.timeout);

    final gemini = TaiLoModelSettings.resolve(
      provider: 'gemini',
      model: 'gemini-2.5-pro',
      current: current,
    );
    expect(gemini.id, 'gemini');
    expect(gemini.model, 'gemini-2.5-pro');
    expect(gemini.apiKeyReference, 'GEMINI_API_KEY');
  });
}
