import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/reminiscence_topic.dart';
import 'ai_models.dart';
import 'ai_service_exception.dart';
import 'provider_response_parser.dart';

class TopicVisionCandidate {
  const TopicVisionCandidate({
    required this.sourceId,
    required this.imageUrl,
    required this.title,
  });

  final String sourceId;
  final String imageUrl;
  final String title;
}

abstract interface class ITopicImageReranker {
  Future<List<String>> rank({
    required ReminiscenceTopic topic,
    required List<TopicVisionCandidate> candidates,
  });
}

class CloudTopicImageReranker implements ITopicImageReranker {
  CloudTopicImageReranker({
    required this.config,
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final VisionProviderConfig config;
  final String apiKey;
  final http.Client _http;

  static const _maxCandidates = 8;
  static const _maxThumbnailBytes = 2 * 1024 * 1024;

  @override
  Future<List<String>> rank({
    required ReminiscenceTopic topic,
    required List<TopicVisionCandidate> candidates,
  }) async {
    if (kIsWeb) {
      throw const AiServiceException(
        AiServiceErrorKind.unsupportedCapability,
        'Web 版未設定安全代理，無法直接使用雲端圖片判斷。',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException(
        AiServiceErrorKind.configuration,
        '尚未設定雲端圖片判斷 Provider 的 API Key。',
      );
    }

    final sheet = await _buildContactSheet(candidates.take(_maxCandidates));
    if (sheet.candidates.isEmpty) return const [];
    final prompt =
        '''
你是台灣回憶治療 App 的圖片審核員。請從聯絡表判斷哪些照片在「實際可見內容」上符合主題，不可只依檔名猜測。

主題：${topic.title}
主題分類：${topic.categoryId}
目標畫面：${topic.imagePrompt}
搜尋語意：${topic.imageSearchQuery}

規則：
1. 必須清楚看得到主題的主要人物、活動、食物或物件。
2. 優先台灣、傳統生活、1950 至 1990 年代氛圍；現代照片只有內容高度相符時才可保留。
3. 排除服裝商品照、空拍建築、神像、標誌、地圖、插畫，以及只和「懷舊」泛泛相關的照片。
4. 不確定就排除；可以全部不選。
5. 只回傳 JSON：{"rankedIndexes":[最適合到較適合的編號]}，不要解釋。編號必須來自聯絡表。
''';

    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    late http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$base/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': config.model,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': prompt},
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url':
                            'data:image/png;base64,${base64Encode(sheet.bytes)}',
                      },
                    },
                  ],
                },
              ],
              'temperature': 0,
              'max_tokens': 512,
              'stream': false,
              ..._providerOptions(),
            }),
          )
          .timeout(config.timeout);
    } on TimeoutException {
      throw AiServiceException(AiServiceErrorKind.timeout, '雲端圖片判斷逾時。');
    } catch (error) {
      if (error is AiServiceException) rethrow;
      throw AiServiceException(
        AiServiceErrorKind.network,
        '無法連線至雲端圖片判斷服務：$error',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiServiceException(
        AiServiceErrorKind.authentication,
        '雲端圖片判斷 API Key 無效或沒有模型權限。',
      );
    }
    if (response.statusCode == 429) {
      throw const AiServiceException(
        AiServiceErrorKind.rateLimit,
        '雲端圖片判斷使用量已達限制。',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        AiServiceErrorKind.network,
        '雲端圖片判斷回傳 HTTP ${response.statusCode}。',
        statusCode: response.statusCode,
      );
    }

    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final raw = extractProviderMessageText(body);
      if (raw == null) {
        throw const FormatException('Provider 沒有回傳文字內容');
      }
      final decoded = decodeJsonObjectFromText(
        raw,
        requiredKey: 'rankedIndexes',
      );
      final indexes = (decoded['rankedIndexes'] as List? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .where((index) => index >= 1 && index <= sheet.candidates.length);
      final seen = <String>{};
      return [
        for (final index in indexes)
          if (seen.add(sheet.candidates[index - 1].sourceId))
            sheet.candidates[index - 1].sourceId,
      ];
    } catch (error) {
      throw AiServiceException(
        AiServiceErrorKind.invalidResponse,
        '雲端圖片判斷回傳格式不正確：$error',
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

  Future<_ContactSheet> _buildContactSheet(
    Iterable<TopicVisionCandidate> input,
  ) async {
    final loaded = <(TopicVisionCandidate, ui.Image)>[];
    for (final candidate in input) {
      try {
        final uri = Uri.parse(candidate.imageUrl);
        if (uri.scheme != 'https') continue;
        final response = await _http.get(uri).timeout(config.timeout);
        final type = response.headers['content-type']?.toLowerCase() ?? '';
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            !type.startsWith('image/') ||
            response.bodyBytes.length > _maxThumbnailBytes) {
          continue;
        }
        final codec = await ui.instantiateImageCodec(
          response.bodyBytes,
          targetWidth: 256,
          targetHeight: 176,
          allowUpscaling: false,
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        loaded.add((candidate, frame.image));
      } catch (_) {
        // One broken candidate must not invalidate the complete contact sheet.
      }
    }
    if (loaded.isEmpty) return _ContactSheet(Uint8List(0), const []);

    const columns = 4;
    const cellWidth = 256.0;
    const cellHeight = 192.0;
    final rows = (loaded.length / columns).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFF3F0E8), ui.BlendMode.src);
    for (var index = 0; index < loaded.length; index++) {
      final x = (index % columns) * cellWidth;
      final y = (index ~/ columns) * cellHeight;
      final image = loaded[index].$2;
      final source = ui.Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final areaWidth = cellWidth;
      final areaHeight = cellHeight - 16;
      final widthScale = areaWidth / image.width;
      final heightScale = areaHeight / image.height;
      final scale = widthScale < heightScale ? widthScale : heightScale;
      final drawnWidth = image.width * scale;
      final drawnHeight = image.height * scale;
      final target = ui.Rect.fromLTWH(
        x + (areaWidth - drawnWidth) / 2,
        y + (areaHeight - drawnHeight) / 2,
        drawnWidth,
        drawnHeight,
      );
      canvas.drawImageRect(image, source, target, ui.Paint());
      canvas.drawRect(
        ui.Rect.fromLTWH(x, y, 42, 38),
        ui.Paint()..color = const ui.Color(0xD9000000),
      );
      final paragraph =
          (ui.ParagraphBuilder(
              ui.ParagraphStyle(fontSize: 24, fontWeight: ui.FontWeight.bold),
            )..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF))))
            ..addText('${index + 1}');
      final label = paragraph.build()
        ..layout(const ui.ParagraphConstraints(width: 42));
      canvas.drawParagraph(label, ui.Offset(x + 12, y + 5));
    }
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      (columns * cellWidth).round(),
      (rows * cellHeight).round(),
    );
    picture.dispose();
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    for (final entry in loaded) {
      entry.$2.dispose();
    }
    return _ContactSheet(
      data?.buffer.asUint8List() ?? Uint8List(0),
      loaded.map((entry) => entry.$1).toList(),
    );
  }
}

class _ContactSheet {
  const _ContactSheet(this.bytes, this.candidates);
  final Uint8List bytes;
  final List<TopicVisionCandidate> candidates;
}
