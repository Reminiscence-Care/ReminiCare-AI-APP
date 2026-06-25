import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:remini_care_ai_app/services/config_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =========================================================================
// 🔑 ReminiCare AI 全域金鑰與動態配置清單 (完全宣告式動態配置引擎)
// =========================================================================
class ReminiCareConfig {
  static final Map<String, String> _configs = {};

  static final List<ConfigField> fields = [
    const ConfigField(
      apiKey: 'NVIDIA_API_KEY',
      displayName: 'NVIDIA API KEY (語言模型)',
      hintText: 'nvapi-...'
    ),
    const ConfigField(
      apiKey: 'GEMINI_API_KEY',
      displayName: "GEMINI API KEY (語言模型)",
      hintText: 'AQ...'
    ),
    const ConfigField(
      apiKey: 'SILICONFLOW_API_KEY',
      displayName: 'SILICONFLOW KEY (影像生成)',
      hintText: 'sk-...'
    ),
    const ConfigField(
      apiKey: 'OPENAI_API_KEY',
      displayName: 'OPENAI API KEY (影像生成)',
      hintText: 'sk-...'
    ),
    const ConfigField(
      apiKey: 'NCKU_TTS_TOKEN',
      displayName: 'NCKU TTS TOKEN (語音合成)',
      hintText: 'Token...'
    ),
    const ConfigField(
      apiKey: 'NCKU_STT_TOKEN',
      displayName: 'NCKU STT TOKEN (成大 ASR)',
      hintText: 'Token...'
    ),
    const ConfigField(
      apiKey: 'YATING_API_KEY',
      displayName: 'Yating TTS/STT TOKEN',
      hintText: 'Token...'
    ),
    const ConfigField(
      apiKey: 'VOICE_MAX_RECORD_LIMIT',
      displayName: 'Voice max recording limit',
      hintText: 'e.x. 180 seconds',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '180'
    ),
    const ConfigField(
      apiKey: 'WAKE_WORDS_START',
      displayName: '語音指令：開始對話 (以逗號隔開)',
      hintText: '開始錄音,開始聊天,開始,來聊,錄音',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '開始錄音,開始聊天,開始,來聊,錄音',
    ),
    const ConfigField(
      apiKey: 'WAKE_WORDS_END',
      displayName: '語音指令：結束對話 (以逗號隔開)',
      hintText: '結束錄音,結束聊天,結束錄影,結束錄像,結束,完成',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '結束錄音,結束聊天,結束錄影,結束錄像,結束,完成',
    ),
    const ConfigField(
      apiKey: 'WAKE_WORDS_RESTART',
      displayName: '語音指令：重新錄音 (以逗號隔開)',
      hintText: '重新錄音,重新聊天,重新,重來,重錄,再來',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '重新錄音,重新聊天,重新,重來,重錄,再來',
    ),
  ];

  static String get nvidiaApiKey => _configs['NVIDIA_API_KEY'] ?? "";
  static String get geminiApiKey => _configs['GEMINI_API_KEY'] ?? "";
  static String get siliconFlowApiKey => _configs['SILICONFLOW_API_KEY'] ?? "";
  static String get openaiApiKey => _configs['OPENAI_API_KEY'] ?? "";
  static String get nckuTtsToken => _configs['NCKU_TTS_TOKEN'] ?? "";
  static String get nckuSttToken => _configs['NCKU_STT_TOKEN'] ?? "";
  static String get yatingApiKey => _configs['YATING_API_KEY'] ?? "";
  static String get spotifyClientId => _configs['SPOTIFY_CLIENT_ID'] ?? "";
  static String get spotifyClientSecret => _configs['SPOTIFY_CLIENT_SECRET'] ?? "";
  static String get maxRecordLimit => _configs['VOICE_MAX_RECORD_LIMIT'] ?? "";
  static int get maxRecordLimitM =>
      int.parse(maxRecordLimit) ~/ 60;

  static int get maxRecordLimitS =>
      int.parse(maxRecordLimit) % 60;
  // 💡 4. 關鍵字動態解析 Getter (相容半形逗號與全形逗號，貼心處理空白)
  static List<String> get startWakeWords => _getWordsList('WAKE_WORDS_START', ["開始錄音", "開始聊天", "開始", "來聊", "錄音"]);
  static List<String> get endWakeWords => _getWordsList('WAKE_WORDS_END', ["結束錄音", "結束聊天", "結束錄影", "結束錄像", "結束", "完成"]);
  static List<String> get restartWakeWords => _getWordsList('WAKE_WORDS_RESTART', ["重新錄音", "重新聊天", "重新", "重來", "重錄", "再來"]);

  static String get ttsCacheName => "tts_audio_cache_index_v1";

  static List<String> _getWordsList(String key, List<String> defaults) {
    final val = getValue(key);
    if (val.isEmpty) return defaults;
    return val
        .replaceAll("，", ",")
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String getValue(String apiKey) => _configs[apiKey] ?? "";

  static Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (var field in fields) {
        String savedVal = prefs.getString(field.apiKey) ?? "";

        if (savedVal.isEmpty && field.hasDefaultValue) {
          savedVal = field.defaultValue;
          await prefs.setString(field.apiKey, savedVal);
        }

        _configs[field.apiKey] = savedVal;
      }

      _configs['selectedLlmProvider'] = prefs.getString('selectedLlmProvider') ?? 'nvidia';
      _configs['selectedSpeechProvider'] = prefs.getString('selectedSpeechProvider') ?? 'yating';
      _configs['selectedImageProvider'] = prefs.getString('selectedImageProvider') ?? 'siliconflow';

      debugPrint("[金鑰管理] 動態加載手機本地快取金鑰完成。");

      bool hasEmptyConfig = _configs.values.any((val) => val.isEmpty);
      if (hasEmptyConfig && !kIsWeb) {
        final envFile = File('.env');
        if (await envFile.exists()) {
          debugPrint("[金鑰管理] 偵測到本地 .env 檔案，正在自動補齊未設定之金鑰...");
          final lines = await envFile.readAsLines();
          for (var line in lines) {
            line = line.trim();
            if (line.isEmpty || line.startsWith('#')) continue;
            final parts = line.split('=');
            if (parts.length >= 2) {
              final key = parts[0].trim();
              final value = parts.sublist(1).join('=').trim();

              if (_configs.containsKey(key) && (_configs[key]?.isEmpty ?? true)) {
                _configs[key] = value;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("[金鑰管理] 加載金鑰時發生異常: $e");
    }
  }

  static Future<void> saveConfig(Map<String, String> newConfigs) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (var entry in newConfigs.entries) {
        final String key = entry.key;
        final String val = entry.value.trim();

        _configs[key] = val;
        await prefs.setString(key, val);
      }

      debugPrint("[金鑰管理] 新金鑰已成功永久儲存至 SharedPreferences 本地資料庫！");
    } catch (e) {
      debugPrint("[金鑰管理] 儲存金鑰至 SharedPreferences 失敗: $e");
    }
  }
}
