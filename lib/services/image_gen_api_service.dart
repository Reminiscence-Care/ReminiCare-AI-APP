import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ==========================================
// 🎨 通用影像生成與修改服務 (Universal Image Service)
// ==========================================
class UniversalImageService {
  final String rawBaseUrl;
  final String Function() apiKeyProvider;
  final String generationModel;
  final String? editModel;
  final String? defaultNegativePrompt;

  String get _baseUrl => kIsWeb ? "https://corsproxy.io/?$rawBaseUrl" : rawBaseUrl;

  UniversalImageService({
    required this.rawBaseUrl,
    required this.apiKeyProvider,
    required this.generationModel,
    this.editModel,
    this.defaultNegativePrompt,
  });

  /// 根據場景參數生成懷舊影像 (💡 核心升級：解除 1980s Taiwan 硬編碼，完全聽從 LLM 推演出的時空背景！)
  Future<String?> generateNostalgicImage({
    required String scene,
    String text = "",
    String era = "1980s",
    String location = "Taiwan",
  }) async {
    debugPrint("🔄 [生圖] 正在呼叫影像 API 生成圖片...");

    // 💡 真正實現動態年代與地點的生成！
    final String basePrompt = (
        "A nostalgic real photography from $era $location, photorealistic, memory atmosphere, warm lighting. "
            "Detailed scene: $scene. "
    );

    debugPrint("👉 [生圖 Prompt]: $basePrompt");

    final url = Uri.parse("$_baseUrl/images/generations");

    final Map<String, dynamic> payload = {
      "model": generationModel,
      "prompt": basePrompt,
      "size": "1024x1024",
      "image_size": "1024x1024",
      "n": 1,
      "batch_size": 1,
    };

    if (defaultNegativePrompt != null && defaultNegativePrompt!.isNotEmpty) {
      payload["negative_prompt"] = defaultNegativePrompt;
    }

    try {
      final response = await http.post(
          url,
          headers: {
            "Authorization": "Bearer ${apiKeyProvider()}",
            "Content-Type": "application/json"
          },
          body: jsonEncode(payload)
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String cloudImageUrl = "";

        if (data['images'] != null && data['images'].isNotEmpty) {
          cloudImageUrl = data['images'][0]['url'];
        } else if (data['data'] != null && data['data'].isNotEmpty) {
          cloudImageUrl = data['data'][0]['url'];
        }

        if (cloudImageUrl.isNotEmpty) {
          return await _downloadAndSave(cloudImageUrl, prefix: "gen");
        }
      } else {
        debugPrint("❌ [生圖失敗] API 異常代碼: ${response.statusCode}, 回傳內容: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ [生圖失敗] 連線錯誤: $e");
    }
    return null;
  }

  /// 對圖片進行修改
  Future<String?> editImage({
    required String imagePath,
    required String editInstruction,
    int? seed,
  }) async {
    if (editModel == null) {
      debugPrint("❌ [改圖失敗] 未提供 editModel 參數");
      return null;
    }
    debugPrint("🔄 [改圖] 正在呼叫 API 修改圖片: '$editInstruction'...");

    if (kIsWeb) return null;

    final file = File(imagePath);
    if (!file.existsSync()) return null;

    try {
      final Uint8List imageBytes = await file.readAsBytes();
      final String encodedString = base64Encode(imageBytes);
      final String base64ImageData = "data:image/png;base64,$encodedString";

      // 💡 這裡我們允許 editInstruction 直接包含時代背景，不再寫死 Taiwan
      final String editPrompt = (
          "A warm, nostalgic real photography. "
              "Based on the original image, $editInstruction. "
              "Keep the existing background untouched, ensure high quality."
      );

      final url = Uri.parse("$_baseUrl/images/generations");

      final Map<String, dynamic> payload = {
        "model": editModel,
        "prompt": editPrompt,
        "image": base64ImageData,
        "size": "1024x1024",
        "image_size": "1024x1024",
      };

      if (defaultNegativePrompt != null && defaultNegativePrompt!.isNotEmpty) {
        payload["negative_prompt"] = defaultNegativePrompt;
      }
      if (seed != null) {
        payload["seed"] = seed;
      }

      final response = await http.post(
          url,
          headers: {
            "Authorization": "Bearer ${apiKeyProvider()}",
            "Content-Type": "application/json"
          },
          body: jsonEncode(payload)
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String cloudImageUrl = "";

        if (data['images'] != null && data['images'].isNotEmpty) {
          cloudImageUrl = data['images'][0]['url'];
        } else if (data['data'] != null && data['data'].isNotEmpty) {
          cloudImageUrl = data['data'][0]['url'];
        }

        if (cloudImageUrl.isNotEmpty) {
          return await _downloadAndSave(cloudImageUrl, prefix: "edit");
        }
      }
    } catch (e) {
      debugPrint("❌ [改圖失敗] 連線與轉換錯誤: $e");
    }
    return null;
  }

  Future<String?> _downloadAndSave(String imageUrl, {required String prefix}) async {
    try {
      final downloadUrl = kIsWeb ? "https://corsproxy.io/?$imageUrl" : imageUrl;
      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode == 200) {
        if (kIsWeb) return imageUrl;

        final directory = await getTemporaryDirectory();
        final String outputPath = "${directory.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.png";

        final file = File(outputPath);
        await file.writeAsBytes(response.bodyBytes);
        return outputPath;
      }
    } catch (e) {
      debugPrint("❌ 圖片本地儲存下載失敗: $e");
    }
    return imageUrl;
  }
}