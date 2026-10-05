import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
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
      'Create a landscape, photorealistic documentary photograph set in '
      '$era $location. Depict the scene as a specific lived memory, with '
      'historically accurate Taiwanese faces, clothing, architecture, tools, '
      'vehicles, food and household objects for that era. Use natural candid '
      'expressions, gentle daylight, realistic skin texture and warm, subtly '
      'faded film colors. Avoid modern objects, modern buildings, staged poses, '
      'generic Chinese scenery, captions, legible signs, logos and watermarks. '
      'Keep the important people and objects away from the image edges. '
      'Scene: $scene';

  String buildEdit({required String instruction}) =>
      'Edit input image 0 according to this requested correction: $instruction. '
      'Preserve the same people, recognizable faces, number of people, camera '
      'angle, composition, lighting, Taiwanese location and historical era. '
      'Change only what the correction requires. Keep a photorealistic '
      'documentary appearance and do not add text, logos or watermarks.';
}

class PreparedImage {
  const PreparedImage(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

class ImageInputPreprocessor {
  const ImageInputPreprocessor();

  Future<PreparedImage> prepare(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const AiServiceException(
        AiServiceErrorKind.configuration,
        '找不到要修改的原始圖片。',
      );
    }
    return compute(_prepareImageBytes, await file.readAsBytes());
  }
}

PreparedImage _prepareImageBytes(Uint8List bytes) {
  final source = img.decodeImage(bytes);
  if (source == null) {
    throw const AiServiceException(
      AiServiceErrorKind.invalidResponse,
      '無法讀取要修改的原始圖片。',
    );
  }
  const maximumEdge = 504;
  final longest = source.width > source.height ? source.width : source.height;
  final resized = longest <= maximumEdge
      ? source
      : img.copyResize(
          source,
          width: source.width >= source.height ? maximumEdge : null,
          height: source.height > source.width ? maximumEdge : null,
          interpolation: img.Interpolation.average,
        );
  return PreparedImage(
    Uint8List.fromList(img.encodeJpg(resized, quality: 88)),
    'image/jpeg',
  );
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
    final extension = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8
        ? 'jpg'
        : 'png';
    final path =
        '${directory.path}${Platform.pathSeparator}${prefix}_${DateTime.now().microsecondsSinceEpoch}.$extension';
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

class CloudflareWorkerImageClient implements IImageGenerationClient {
  CloudflareWorkerImageClient({
    required this.config,
    required this.appToken,
    http.Client? httpClient,
    LocalImageStore? store,
    ImageInputPreprocessor? preprocessor,
  }) : _http = httpClient ?? http.Client(),
       _store = store ?? LocalImageStore(),
       _preprocessor = preprocessor ?? const ImageInputPreprocessor();

  @override
  final ImageProviderConfig config;
  final String appToken;
  final http.Client _http;
  final LocalImageStore _store;
  final ImageInputPreprocessor _preprocessor;

  @override
  Future<String> generate({required String prompt}) => _request(
    endpoint: 'generations',
    payload: {'prompt': prompt, 'width': 1024, 'height': 640},
    prefix: 'generated',
  );

  @override
  Future<String> edit({
    required String imagePath,
    required String instruction,
  }) async {
    if (!config.supports(ProviderCapability.imageEditing)) {
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
    final prepared = await _preprocessor.prepare(imagePath);
    return _request(
      endpoint: 'edits',
      payload: {
        'prompt': const NostalgicImagePromptBuilder().buildEdit(
          instruction: instruction,
        ),
        'imageBase64': base64Encode(prepared.bytes),
        'imageMimeType': prepared.mimeType,
        'width': 1024,
        'height': 640,
      },
      prefix: 'edited',
    );
  }

  Future<String> _request({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String prefix,
  }) async {
    if (kIsWeb) {
      throw const AiServiceException(
        AiServiceErrorKind.unsupportedCapability,
        'Web 版未啟用圖片服務。',
      );
    }
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const AiServiceException(
        AiServiceErrorKind.configuration,
        'Cloudflare Worker URL 必須是有效的 HTTPS 網址。',
      );
    }
    if (appToken.trim().isEmpty) {
      throw const AiServiceException(
        AiServiceErrorKind.configuration,
        '尚未設定 Cloudflare Image App Token。',
      );
    }
    try {
      final response = await _http
          .post(
            Uri.parse('$base/v1/images/$endpoint'),
            headers: {
              'Authorization': 'Bearer $appToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(config.timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AiServiceException(
          AiServiceErrorKind.authentication,
          'Cloudflare Image App Token 無效。',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 429) {
        throw const AiServiceException(
          AiServiceErrorKind.rateLimit,
          'Cloudflare 生圖請求過於頻繁或今日額度已達限制；可稍後重試，或到設定頁手動切換 Provider。',
          statusCode: 429,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiServiceException(
          AiServiceErrorKind.network,
          'Cloudflare 生圖服務回傳 HTTP ${response.statusCode}。${_cloudflareError(response.bodyBytes)}',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      final item = data is List && data.isNotEmpty ? data.first : null;
      final encoded = item is Map<String, dynamic>
          ? item['b64_json']?.toString()
          : null;
      if (encoded == null || encoded.isEmpty) {
        throw const AiServiceException(
          AiServiceErrorKind.invalidResponse,
          'Cloudflare 生圖服務沒有回傳圖片資料。',
        );
      }
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) {
        throw const FormatException('Empty image');
      }
      return await _store.save(bytes, prefix: prefix);
    } on TimeoutException {
      throw const AiServiceException(
        AiServiceErrorKind.timeout,
        'Cloudflare 生圖請求逾時。',
      );
    } on AiServiceException {
      rethrow;
    } on FormatException {
      throw const AiServiceException(
        AiServiceErrorKind.invalidResponse,
        'Cloudflare 生圖服務回傳的圖片格式不正確。',
      );
    } catch (error) {
      throw AiServiceException(
        AiServiceErrorKind.network,
        'Cloudflare 生圖連線失敗：$error',
      );
    }
  }

  String _cloudflareError(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final message = error is Map<String, dynamic>
          ? error['message']?.toString()
          : null;
      return message == null || message.trim().isEmpty ? '' : ' $message';
    } catch (_) {
      return '';
    }
  }
}
