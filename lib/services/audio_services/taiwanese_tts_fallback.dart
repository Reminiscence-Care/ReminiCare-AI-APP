import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../ai/ai_models.dart';
import '../ai/llm_client.dart';
import '../ai/provider_registry.dart';
import '../ai/provider_response_parser.dart';

/// 成大 9998 台語直接輸入漢字失敗時的備援順序。
///
/// 主要路徑永遠是 9998 直接合成；以下模式只決定失敗後要不要再試：
/// - [llmThenLegacy]：先請 LLM 轉台羅再送 9998，仍失敗才用 10012 舊伺服器。
/// - [llmOnly]：只用 LLM 轉台羅。
/// - [legacyOnly]：直接改用 10012 舊伺服器（音質較差）。
/// - [off]：不備援。
enum TaiwaneseTtsFallback {
  llmThenLegacy('llm_legacy', 'LLM 轉台羅 → 舊伺服器'),
  llmOnly('llm', '只用 LLM 轉台羅'),
  legacyOnly('legacy', '只用舊伺服器（音質較差）'),
  off('off', '不備援');

  const TaiwaneseTtsFallback(this.id, this.label);
  final String id;
  final String label;

  static const configKey = 'NCKU_TW_TTS_FALLBACK';
  static const defaultMode = llmThenLegacy;

  static TaiwaneseTtsFallback parse(String? raw) => values.firstWhere(
    (mode) => mode.id == raw?.trim(),
    orElse: () => defaultMode,
  );

  bool get usesLlm => this == llmThenLegacy || this == llmOnly;
  bool get usesLegacy => this == llmThenLegacy || this == legacyOnly;
}

/// 轉台羅專用的模型設定，和回憶聊天用的語言模型分開。
///
/// 2026-11-06 實測：NVIDIA deepseek-v4.1-flash 每句約 66 秒且答案落在推理欄位；
/// OpenAI gpt-4.1 約 5 秒、台語用字最好，所以預設用 OpenAI gpt-4.1。
abstract final class TaiLoModelSettings {
  static const providerKey = 'TAILO_LLM_PROVIDER';
  static const modelKey = 'TAILO_LLM_MODEL';
  static const followCurrent = 'current';
  static const defaultProvider = 'openai';
  static const timeout = Duration(seconds: 25);

  static const providers = <String, String>{
    'openai': 'OpenAI（建議）',
    'gemini': 'Google Gemini',
    'nvidia': 'NVIDIA（目前很慢，不建議）',
    followCurrent: '跟隨上方語言模型',
  };

  /// 留白時使用的模型；沒列出的 Provider 用它在 ProviderRegistry 的預設。
  static const defaultModels = <String, String>{'openai': 'gpt-4.1'};

  static String parseProvider(String? raw) {
    final value = raw?.trim() ?? '';
    return providers.containsKey(value) ? value : defaultProvider;
  }

  /// 依設定組出轉台羅用的 LLM；[current] 是回憶聊天目前使用的語言模型。
  static LlmProviderConfig resolve({
    required String? provider,
    required String? model,
    required LlmProviderConfig current,
  }) {
    final id = parseProvider(provider);
    final base = id == followCurrent
        ? current
        : ProviderRegistry.llmPresets[id]!;
    final custom = model?.trim() ?? '';
    return LlmProviderConfig(
      id: base.id,
      displayName: base.displayName,
      baseUrl: base.baseUrl,
      model: custom.isNotEmpty ? custom : defaultModels[id] ?? base.model,
      apiKeyReference: base.apiKeyReference,
      timeout: timeout,
      isCustom: base.isCustom,
    );
  }
}

final _han = RegExp(
  r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u{20000}-\u{3134F}]',
  unicode: true,
);

/// 文字是否含有漢字（9998 台語目前只接受台羅）。
bool containsHan(String text) => _han.hasMatch(text);

const _punctuation = {
  '，': ',',
  '、': ',',
  '；': ',',
  '：': ',',
  '。': '.',
  '．': '.',
  '…': '.',
  '？': '?',
  '！': '!',
  '「': '',
  '」': '',
  '『': '',
  '』': '',
  '（': '',
  '）': '',
  '"': '',
  '“': '',
  '”': '',
};

/// 整理 LLM 回傳的台羅；不是可送出的純台羅時回傳 null。
String? normalizeTaiLo(Object? value) {
  if (value is! String) return null;
  var text = value;
  _punctuation.forEach(
    (from, to) => text = text.replaceAll(from, to.isEmpty ? ' ' : '$to '),
  );
  text = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r' ([,.?!])'), (m) => m[1]!)
      .trim();
  if (text.isEmpty ||
      containsHan(text) ||
      text.contains('@@@') ||
      !RegExp(r'[A-Za-z]').hasMatch(text)) {
    return null;
  }
  return text;
}

abstract interface class TaiLoConverter {
  /// 把華語或台語漢字轉成台羅；無法轉換時回傳 null 或丟出例外。
  Future<String?> toTaiLo(String text, {Duration? timeout});
}

class LlmTaiLoConverter implements TaiLoConverter {
  LlmTaiLoConverter(this._client);
  final LlmClient _client;

  @override
  Future<String?> toTaiLo(String text, {Duration? timeout}) async {
    final request = _client.complete(
      messages: [
        const LlmMessage(
          'system',
          '你是臺灣台語（閩南語）語言專家，負責把文字轉成教育部「臺灣台語羅馬字拼音方案」（台羅）'
              '給語音合成使用。只輸出合法 JSON。',
        ),
        LlmMessage(
          'user',
          '把下面的文字轉成台羅。規則：\n'
              '1. 輸入可能是華語或台語漢字；先改成自然、口語、長輩聽得懂的台語說法，意思不可增減。\n'
              '2. 用調號標聲調（例如 á à â ā a̍ a̋），不要用數字調；第一、四聲不標。\n'
              '3. 同一個詞的音節用連字號連接，詞與詞之間空一格；只寫本調，不標變調。\n'
              '4. 不可出現任何漢字；人名、地名也要轉台羅，數字、日期、時間改成台語唸法。\n'
              '5. 標點只用 , . ? !\n'
              '6. 只回傳 {"tailo":"..."}，不要解釋。\n'
              '文字：${jsonEncode(text)}',
        ),
      ],
      temperature: 0.1,
      maxTokens: (text.runes.length * 12).clamp(1200, 6000),
      jsonObject: true,
    );
    final raw = timeout == null
        ? await request
        : await request.timeout(timeout);
    final data = decodeJsonObjectFromText(raw, requiredKey: 'tailo');
    return normalizeTaiLo(data['tailo']);
  }
}

abstract interface class LegacyTaiwaneseTts {
  /// 回傳 WAV 位元組；失敗回傳 null。
  Future<Uint8List?> synthesize(String text, {Duration? timeout});
}

/// 成大舊版 HTS 台語伺服器（樹莓派課程 `mi2s_tts.py` 的協定）。
///
/// 封包：4-byte big-endian 長度 + `token@@@text@@@model@@@taiwanese`，
/// 伺服器直接回傳 WAV 後關閉連線。可輸入漢字，但音質與正確度較差。
class NckuLegacyTaiwaneseTts implements LegacyTaiwaneseTts {
  NckuLegacyTaiwaneseTts({
    required this.token,
    this.host = defaultHost,
    this.port = defaultPort,
    this.model = defaultModel,
  });

  static const defaultHost = '140.116.245.157';
  static const defaultPort = 10012;
  static const defaultModel = 'M04';
  static const maximumBytes = 50 * 1024 * 1024;

  final String Function() token;
  final String host;
  final int port;
  final String model;

  @override
  Future<Uint8List?> synthesize(String text, {Duration? timeout}) async {
    if (text.isEmpty || text.contains('@@@')) return null;
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      final payload = utf8.encode('${token()}@@@$text@@@$model@@@taiwanese');
      final header = ByteData(4)..setUint32(0, payload.length);
      socket.add(header.buffer.asUint8List());
      socket.add(payload);
      await socket.flush();

      final builder = BytesBuilder(copy: false);
      final done = socket.forEach((chunk) {
        builder.add(chunk);
        if (builder.length > maximumBytes) {
          throw const FormatException('legacy TTS response too large');
        }
      });
      await done.timeout(timeout ?? const Duration(seconds: 60));
      final bytes = builder.takeBytes();
      final isWav =
          bytes.length > 44 &&
          bytes[0] == 0x52 && // R
          bytes[1] == 0x49 && // I
          bytes[2] == 0x46 && // F
          bytes[3] == 0x46; // F
      return isWav ? bytes : null;
    } finally {
      socket?.destroy();
    }
  }
}
