import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ai/ai_models.dart';
import 'ai/ai_service_exception.dart';

abstract interface class IImageGenerationClient {
  ImageProviderConfig get config;
  Future<String> generate({required String prompt});
  Future<String> edit({required String imagePath, required String instruction});
}

class NostalgicImagePromptBuilder {
  const NostalgicImagePromptBuilder();

  String build({
    required String scene,
    String era = '1960s-1980s',
    String location = 'Taiwan',
  }) =>
      'A warm photorealistic documentary photograph from $era $location. '
      'Authentic Taiwanese people, architecture, clothing and objects. '
      'Natural expressions, gentle daylight, rich memory atmosphere. '
      'No captions, no signs, no watermark. Scene: $scene';
}

class LocalImageStore {
  Future<String> save(Uint8List bytes, {required String prefix}) async {
    if (kIsWeb) {
      throw const AiServiceException(
        AiServiceErrorKind.unsupportedCapability,
        'Web 版未設定安全圖片代理。',
      );
    }
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}reminicare_images',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final path =
        '${directory.path}${Platform.pathSeparator}${prefix}_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}

class OpenAiCompatibleImageClient implements IImageGenerationClient {
  OpenAiCompatibleImageClient({
    required this.config,
    required this.apiKey,
    http.Client? httpClient,
    LocalImageStore? store,
  }) : _http = httpClient ?? http.Client(),
       _store = store ?? LocalImageStore();

  @override
  final ImageProviderConfig config;
  final String apiKey;
  final http.Client _http;
  final LocalImageStore _store;

  @override
  Future<String> generate({required String prompt}) => _request(
    payload: {
      'model': config.generationModel,
      'prompt': prompt,
      'n': 1,
      'size': '1024x1024',
    },
    prefix: 'generated',
  );

  @override
  Future<String> edit({
    required String imagePath,
    required String instruction,
  }) async {
    if (!config.supports(ProviderCapability.imageEditing) ||
        config.editModel == null) {
      throw const AiServiceException(
        AiServiceErrorKind.unsupportedCapability,
        '目前的生圖 Provider 不支援原圖編輯。',
      );
    }
    if (kIsWeb) {
      throw const AiServiceException(
        AiServiceErrorKind.unsupportedCapability,
        'Web 版不支援直接改圖。',
      );
    }
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const AiServiceException(
        AiServiceErrorKind.configuration,
        '找不到要修改的原始圖片。',
      );
    }
    final encoded = base64Encode(await file.readAsBytes());
    return _request(
      payload: {
        'model': config.editModel,
        'prompt': instruction,
        'image': 'data:image/png;base64,$encoded',
        'size': '1024x1024',
      },
      prefix: 'edited',
    );
  }

  Future<String> _request({
    required Map<String, dynamic> payload,
    required String prefix,
  }) async {
    if (kIsWeb) {
      throw const AiServiceException(
        AiServiceErrorKind.unsupportedCapability,
        'Web 版未設定安全後端代理，為避免洩漏 API Key 已停用直接呼叫。',
      );
    }
    if (apiKey.isEmpty) {
      throw const AiServiceException(
        AiServiceErrorKind.configuration,
        '尚未設定生圖 API Key。',
      );
    }
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _http
          .post(
            Uri.parse('$base/images/generations'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(config.timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AiServiceException(
          AiServiceErrorKind.authentication,
          '生圖 API Key 無效。${_errorDetail(response.bodyBytes)}',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 429) {
        throw AiServiceException(
          AiServiceErrorKind.rateLimit,
          '生圖使用量已達限制。',
          statusCode: 429,
        );
      }
      if (response.statusCode == 402) {
        throw AiServiceException(
          AiServiceErrorKind.billing,
          '生圖 Provider 餘額不足或付款設定未完成。${_errorDetail(response.bodyBytes)}',
          statusCode: 402,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          AiServiceErrorKind.network,
          '生圖 Provider 回傳 HTTP ${response.statusCode}。${_errorDetail(response.bodyBytes)}',
          statusCode: response.statusCode,
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final item = _firstImage(data);
      final b64 = item['b64_json']?.toString();
      if (b64 != null && b64.isNotEmpty) {
        return await _store.save(base64Decode(b64), prefix: prefix);
      }
      final url = item['url']?.toString();
      if (url == null || url.isEmpty) {
        throw const AiServiceException(
          AiServiceErrorKind.invalidResponse,
          '生圖回應沒有圖片資料。',
        );
      }
      final download = await _http.get(Uri.parse(url)).timeout(config.timeout);
      if (download.statusCode < 200 || download.statusCode >= 300) {
        throw AiServiceException(
          AiServiceErrorKind.network,
          '圖片下載失敗：HTTP ${download.statusCode}。',
        );
      }
      return await _store.save(download.bodyBytes, prefix: prefix);
    } on TimeoutException {
      throw const AiServiceException(AiServiceErrorKind.timeout, '生圖請求逾時。');
    } on AiServiceException {
      rethrow;
    } catch (error) {
      throw AiServiceException(AiServiceErrorKind.network, '生圖連線失敗：$error');
    }
  }

  Map<String, dynamic> _firstImage(dynamic decoded) {
    for (final key in const ['data', 'images']) {
      final list = decoded is Map<String, dynamic> ? decoded[key] : null;
      if (list is List &&
          list.isNotEmpty &&
          list.first is Map<String, dynamic>) {
        return list.first as Map<String, dynamic>;
      }
    }
    throw const AiServiceException(
      AiServiceErrorKind.invalidResponse,
      '無法解析生圖 Provider 回應。',
    );
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
