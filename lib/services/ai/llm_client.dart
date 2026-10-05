import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_models.dart';
import 'ai_service_exception.dart';
import 'provider_response_parser.dart';

abstract interface class LlmClient {
  Future<String> complete({
    required List<LlmMessage> messages,
    double temperature = 0.6,
    int maxTokens = 500,
    bool jsonObject = false,
  });
}

class OpenAiCompatibleLlmClient implements LlmClient {
  OpenAiCompatibleLlmClient({
    required this.config,
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final LlmProviderConfig config;
  final String apiKey;
  final http.Client _http;

  @override
  Future<String> complete({
    required List<LlmMessage> messages,
    double temperature = 0.6,
    int maxTokens = 500,
    bool jsonObject = false,
  }) async {
    if (kIsWeb) {
      throw const AiServiceException(
        AiServiceErrorKind.unsupportedCapability,
        'Web 版未設定安全後端代理，為避免洩漏 API Key 已停用直接呼叫。',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException(
        AiServiceErrorKind.configuration,
        '尚未設定此 Provider 的 API Key。',
      );
    }

    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _http
          .post(
            Uri.parse('$base/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': config.model,
              'messages': messages.map((m) => m.toJson()).toList(),
              'temperature': temperature,
              'max_tokens': maxTokens,
              if (jsonObject) 'response_format': {'type': 'json_object'},
              ..._providerOptions(),
            }),
          )
          .timeout(config.timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AiServiceException(
          AiServiceErrorKind.authentication,
          'API Key 無效或沒有模型權限。${_errorDetail(response.bodyBytes)}',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 429) {
        throw AiServiceException(
          AiServiceErrorKind.rateLimit,
          'API 使用量已達限制，請稍後再試。',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 402) {
        throw AiServiceException(
          AiServiceErrorKind.billing,
          'AI Provider 餘額不足或付款設定未完成。${_errorDetail(response.bodyBytes)}',
          statusCode: 402,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          AiServiceErrorKind.network,
          'Provider 回傳 HTTP ${response.statusCode}。${_errorDetail(response.bodyBytes)}',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final text = extractProviderMessageText(decoded);
      if (text == null || text.isEmpty) {
        final choices = decoded is Map<String, dynamic>
            ? decoded['choices']
            : null;
        final first = choices is List && choices.isNotEmpty
            ? choices.first
            : null;
        final finishReason = first is Map ? first['finish_reason'] : null;
        throw AiServiceException(
          AiServiceErrorKind.invalidResponse,
          finishReason == 'length'
              ? 'Provider 的輸出額度被推理內容用完，沒有產生最終答案。'
              : 'Provider 沒有回傳文字內容。',
        );
      }
      return text;
    } on TimeoutException {
      throw const AiServiceException(AiServiceErrorKind.timeout, 'AI 請求逾時。');
    } on AiServiceException {
      rethrow;
    } on FormatException catch (error) {
      throw AiServiceException(
        AiServiceErrorKind.invalidResponse,
        '無法解析 Provider 回應：$error',
      );
    } catch (error) {
      throw AiServiceException(
        AiServiceErrorKind.network,
        '無法連線至 AI Provider：$error',
      );
    }
  }

  Map<String, dynamic> _providerOptions() {
    if (config.id != 'nvidia') return const {};
    final model = config.model.toLowerCase();
    if (model.contains('glm-5.3')) {
      return const {
        'reasoning_effort': 'low',
        'chat_template_kwargs': {'clear_thinking': true},
      };
    }
    if (model.contains('deepseek-v4.1')) {
      return const {'reasoning_effort': 'low'};
    }
    return const {};
  }

  String _errorDetail(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final message = error is Map<String, dynamic>
          ? error['message']?.toString()
          : error?.toString() ??
                (decoded is Map<String, dynamic>
                    ? decoded['message']?.toString()
                    : null);
      if (message == null || message.trim().isEmpty) return '';
      final compact = message.replaceAll(RegExp(r'\s+'), ' ').trim();
      return ' ${compact.length > 240 ? compact.substring(0, 240) : compact}';
    } catch (_) {
      return '';
    }
  }
}
