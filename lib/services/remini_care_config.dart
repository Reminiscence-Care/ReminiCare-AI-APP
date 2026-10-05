import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config_field.dart';

abstract final class ReminiCareConfig {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _migrationMarker = 'secure_storage_migration_v1';
  static final Map<String, String> _configs = {};
  static int _revision = 0;

  static const Set<String> secretKeys = {
    'NVIDIA_API_KEY',
    'GEMINI_API_KEY',
    'OPENAI_API_KEY',
    'SILICONFLOW_API_KEY',
    'CLOUDFLARE_IMAGE_APP_TOKEN',
    'CUSTOM_LLM_API_KEY',
    'CUSTOM_IMAGE_API_KEY',
    'CUSTOM_VISION_API_KEY',
    'NCKU_TTS_TOKEN',
    'NCKU_STT_TOKEN',
    'YATING_API_KEY',
  };

  static const fields = <ConfigField>[
    ConfigField(
      apiKey: 'VOICE_INTRO_SILENCE_SECONDS',
      displayName: '自我介紹：說完後等待秒數（1–30）',
      hintText: '3',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '3',
    ),
    ConfigField(
      apiKey: 'VOICE_CHAT_SILENCE_SECONDS',
      displayName: '聊天／修圖：說完後等待秒數（1–30）',
      hintText: '6',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '6',
    ),
    ConfigField(
      apiKey: 'NVIDIA_API_KEY',
      displayName: 'NVIDIA API Key',
      hintText: 'nvapi-...',
    ),
    ConfigField(
      apiKey: 'GEMINI_API_KEY',
      displayName: 'Gemini API Key',
      hintText: 'AIza...',
    ),
    ConfigField(
      apiKey: 'OPENAI_API_KEY',
      displayName: 'OpenAI API Key',
      hintText: 'sk-...',
    ),
    ConfigField(
      apiKey: 'SILICONFLOW_API_KEY',
      displayName: 'SiliconFlow API Key',
      hintText: 'sk-...',
    ),
    ConfigField(
      apiKey: 'CLOUDFLARE_IMAGE_APP_TOKEN',
      displayName: 'Cloudflare Image App Token',
      hintText: '與 Worker APP_API_TOKEN 相同的值',
    ),
    ConfigField(
      apiKey: 'CLOUDFLARE_IMAGE_WORKER_URL',
      displayName: 'Cloudflare Image Worker URL',
      hintText: 'https://reminicare-image-api.<subdomain>.workers.dev',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: 'https://reminicare-image-api.hding49.workers.dev',
    ),
    ConfigField(
      apiKey: 'CUSTOM_LLM_API_KEY',
      displayName: 'Custom LLM API Key',
      hintText: 'sk-...',
    ),
    ConfigField(
      apiKey: 'CUSTOM_IMAGE_API_KEY',
      displayName: 'Custom Image API Key',
      hintText: 'sk-...',
    ),
    ConfigField(
      apiKey: 'CUSTOM_VISION_API_KEY',
      displayName: 'Custom Vision API Key',
      hintText: 'sk-...',
    ),
    ConfigField(
      apiKey: 'NCKU_TTS_TOKEN',
      displayName: 'NCKU TTS Token',
      hintText: 'Token...',
    ),
    ConfigField(
      apiKey: 'NCKU_STT_TOKEN',
      displayName: 'NCKU STT Token',
      hintText: 'Token...',
    ),
    ConfigField(
      apiKey: 'YATING_API_KEY',
      displayName: 'Yating TTS/STT Token',
      hintText: 'Token...',
    ),
    ConfigField(
      apiKey: 'CUSTOM_LLM_BASE_URL',
      displayName: 'Custom LLM Base URL',
      hintText: 'https://example.com/v1',
      isSecure: false,
    ),
    ConfigField(
      apiKey: 'CUSTOM_LLM_MODEL',
      displayName: 'Custom LLM 模型',
      hintText: 'model-name',
      isSecure: false,
    ),
    ConfigField(
      apiKey: 'CUSTOM_IMAGE_BASE_URL',
      displayName: 'Custom Image Base URL',
      hintText: 'https://example.com/v1',
      isSecure: false,
    ),
    ConfigField(
      apiKey: 'CUSTOM_IMAGE_MODEL',
      displayName: 'Custom 生圖模型',
      hintText: 'model-name',
      isSecure: false,
    ),
    ConfigField(
      apiKey: 'CUSTOM_VISION_BASE_URL',
      displayName: 'Custom Vision Base URL',
      hintText: 'https://example.com/v1',
      isSecure: false,
    ),
    ConfigField(
      apiKey: 'CUSTOM_VISION_MODEL',
      displayName: 'Custom Vision 模型',
      hintText: 'vision-model-name',
      isSecure: false,
    ),
    ConfigField(
      apiKey: 'NVIDIA_LLM_MODEL',
      displayName: 'NVIDIA LLM 模型',
      hintText: 'deepseek-ai/deepseek-v4.1-flash',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: 'deepseek-ai/deepseek-v4.1-flash',
    ),
    ConfigField(
      apiKey: 'OPENAI_LLM_MODEL',
      displayName: 'OpenAI LLM 模型',
      hintText: 'gpt-4o-mini',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: 'gpt-4o-mini',
    ),
    ConfigField(
      apiKey: 'GEMINI_LLM_MODEL',
      displayName: 'Gemini LLM 模型',
      hintText: 'gemini-2.5-flash',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: 'gemini-2.5-flash',
    ),
    ConfigField(
      apiKey: 'NVIDIA_VISION_MODEL',
      displayName: 'NVIDIA Vision 模型',
      hintText: 'meta/llama-3.2-11b-vision-instruct',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: 'meta/llama-3.2-11b-vision-instruct',
    ),
    ConfigField(
      apiKey: 'OPENAI_VISION_MODEL',
      displayName: 'OpenAI Vision 模型',
      hintText: 'gpt-4o-mini',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: 'gpt-4o-mini',
    ),
    ConfigField(
      apiKey: 'GEMINI_VISION_MODEL',
      displayName: 'Gemini Vision 模型',
      hintText: 'gemini-2.5-flash',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: 'gemini-2.5-flash',
    ),
    ConfigField(
      apiKey: 'VOICE_MAX_RECORD_LIMIT',
      displayName: '最長錄音秒數',
      hintText: '180',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '180',
    ),
    ConfigField(
      apiKey: 'WAKE_WORDS_START',
      displayName: '開始對話喚醒詞',
      hintText: '開始錄音,開始聊天',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '開始錄音,開始聊天,開始,來聊,錄音',
    ),
    ConfigField(
      apiKey: 'WAKE_WORDS_END',
      displayName: '結束對話喚醒詞',
      hintText: '結束錄音,完成',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '結束錄音,結束聊天,結束,完成',
    ),
    ConfigField(
      apiKey: 'WAKE_WORDS_RESTART',
      displayName: '重新錄音喚醒詞',
      hintText: '重新錄音,重來',
      isSecure: false,
      hasDefaultValue: true,
      defaultValue: '重新錄音,重新聊天,重新,重來,重錄,再來',
    ),
  ];

  static int get revision => _revision;
  static String get nvidiaApiKey => getValue('NVIDIA_API_KEY');
  static String get geminiApiKey => getValue('GEMINI_API_KEY');
  static String get openaiApiKey => getValue('OPENAI_API_KEY');
  static String get siliconFlowApiKey => getValue('SILICONFLOW_API_KEY');
  static String get nckuTtsToken => getValue('NCKU_TTS_TOKEN');
  static String get nckuSttToken => getValue('NCKU_STT_TOKEN');
  static String get yatingApiKey => getValue('YATING_API_KEY');
  static String get maxRecordLimit => getValue('VOICE_MAX_RECORD_LIMIT');
  static int get maxRecordLimitM => (int.tryParse(maxRecordLimit) ?? 180) ~/ 60;
  static int get maxRecordLimitS => (int.tryParse(maxRecordLimit) ?? 180) % 60;
  static String get ttsCacheName => 'tts_audio_cache_index_v1';
  static List<String> get startWakeWords => _wordList('WAKE_WORDS_START');
  static List<String> get endWakeWords => _wordList('WAKE_WORDS_END');
  static List<String> get restartWakeWords => _wordList('WAKE_WORDS_RESTART');
  static String getValue(String key) => _configs[key] ?? '';

  static Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateSecrets(prefs);
    for (final field in fields) {
      var value = secretKeys.contains(field.apiKey)
          ? await _secureStorage.read(key: field.apiKey) ?? ''
          : prefs.getString(field.apiKey) ?? '';
      if (value.isEmpty && field.hasDefaultValue) {
        value = field.defaultValue;
        await prefs.setString(field.apiKey, value);
      }
      _configs[field.apiKey] = value;
    }
    _configs['selectedLlmProvider'] =
        prefs.getString('selectedLlmProvider') ?? 'nvidia';
    _configs['selectedSpeechProvider'] =
        prefs.getString('selectedSpeechProvider') ?? 'yating';
    _configs['selectedImageProvider'] =
        prefs.getString('selectedImageProvider') ?? 'cloudflare';
    _configs['selectedVisionProvider'] =
        prefs.getString('selectedVisionProvider') ?? 'nvidia';
    if (kDebugMode && !kIsWeb) await _readDebugEnv();
    _revision++;
  }

  static Future<void> saveConfig(Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      final value = entry.value.trim();
      _configs[entry.key] = value;
      if (secretKeys.contains(entry.key)) {
        if (value.isEmpty) {
          await _secureStorage.delete(key: entry.key);
        } else {
          await _secureStorage.write(key: entry.key, value: value);
        }
        await prefs.remove(entry.key);
      } else {
        await prefs.setString(entry.key, value);
      }
    }
    _revision++;
  }

  static String? validateProviderSettings(Map<String, String> values) {
    String read(String key) => (values[key] ?? getValue(key)).trim();
    for (final key in [
      'VOICE_INTRO_SILENCE_SECONDS',
      'VOICE_CHAT_SILENCE_SECONDS',
    ]) {
      final raw = values.containsKey(key)
          ? read(key)
          : (read(key).isEmpty
                ? (key == 'VOICE_INTRO_SILENCE_SECONDS' ? '3' : '6')
                : read(key));
      final number = double.tryParse(raw);
      if (number == null ||
          !number.isFinite ||
          number < 1 ||
          number > 30 ||
          !RegExp(r'^\d+(\.\d)?$').hasMatch(raw)) {
        return '${key == 'VOICE_INTRO_SILENCE_SECONDS' ? '自我介紹' : '聊天／修圖'}等待時間需為 1–30 秒，最多小數一位';
      }
    }
    final llm = read('selectedLlmProvider').isEmpty
        ? 'nvidia'
        : read('selectedLlmProvider');
    final image = read('selectedImageProvider').isEmpty
        ? 'cloudflare'
        : read('selectedImageProvider');
    final speech = read('selectedSpeechProvider').isEmpty
        ? 'yating'
        : read('selectedSpeechProvider');
    final llmKey = switch (llm) {
      'openai' => 'OPENAI_API_KEY',
      'gemini' => 'GEMINI_API_KEY',
      'custom' => 'CUSTOM_LLM_API_KEY',
      _ => 'NVIDIA_API_KEY',
    };
    final imageKey = switch (image) {
      'cloudflare' => 'CLOUDFLARE_IMAGE_APP_TOKEN',
      'openai' => 'OPENAI_API_KEY',
      'custom' => 'CUSTOM_IMAGE_API_KEY',
      _ => 'SILICONFLOW_API_KEY',
    };
    final llmModelKey = switch (llm) {
      'openai' => 'OPENAI_LLM_MODEL',
      'gemini' => 'GEMINI_LLM_MODEL',
      'custom' => 'CUSTOM_LLM_MODEL',
      _ => 'NVIDIA_LLM_MODEL',
    };
    if (read(llmKey).isEmpty) return '目前語言模型的 API Key 不可空白';
    if (read(imageKey).isEmpty) return '目前生圖服務的 API Key 不可空白';
    if (read(llmModelKey).isEmpty) return '目前語言模型名稱不可空白';
    if (speech == 'ncku' &&
        (read('NCKU_TTS_TOKEN').isEmpty || read('NCKU_STT_TOKEN').isEmpty)) {
      return 'NCKU 語音服務需要 TTS 與 STT Token';
    }
    if (speech != 'ncku' && read('YATING_API_KEY').isEmpty) {
      return '雅婷語音服務 Token 不可空白';
    }
    if (llm == 'custom') {
      final error = _validateCustom(
        read('CUSTOM_LLM_BASE_URL'),
        read('CUSTOM_LLM_MODEL'),
      );
      if (error != null) return '自訂 LLM：$error';
    }
    if (image == 'custom') {
      final error = _validateCustom(
        read('CUSTOM_IMAGE_BASE_URL'),
        read('CUSTOM_IMAGE_MODEL'),
      );
      if (error != null) return '自訂生圖：$error';
    }
    if (image == 'cloudflare') {
      final uri = Uri.tryParse(read('CLOUDFLARE_IMAGE_WORKER_URL'));
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        return 'Cloudflare Worker URL 必須是有效的 HTTPS 網址';
      }
    }
    return null;
  }

  static String? _validateCustom(String? rawUrl, String? model) {
    final uri = Uri.tryParse((rawUrl ?? '').trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Base URL 必須是有效的 HTTPS 網址';
    }
    if ((model ?? '').trim().isEmpty) return '模型名稱不可空白';
    return null;
  }

  static Future<void> _migrateSecrets(SharedPreferences prefs) async {
    if (prefs.getBool(_migrationMarker) == true) return;
    for (final key in secretKeys) {
      final legacy = prefs.getString(key);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await _secureStorage.write(key: key, value: legacy.trim());
      }
      await prefs.remove(key);
    }
    await prefs.setBool(_migrationMarker, true);
  }

  static Future<void> _readDebugEnv() async {
    final file = File('.env');
    if (!await file.exists()) return;
    for (var line in await file.readAsLines()) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
      final index = line.indexOf('=');
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim();
      if (_configs.containsKey(key) && getValue(key).isEmpty) {
        _configs[key] = value;
      }
    }
  }

  static List<String> _wordList(String key) => getValue(key)
      .replaceAll('，', ',')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
