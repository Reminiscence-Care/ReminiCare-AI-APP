import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';


// ==========================================
// 🎨 SiliconFlow 影像生成與修改服務 (Qwen-Image)
// ==========================================
class SiliconFlowImageService {
  final String _rawBaseUrl = "https://api.siliconflow.com/v1";

  String get _baseUrl => kIsWeb ? "https://corsproxy.io/?$_rawBaseUrl" : _rawBaseUrl;

  final String _generationModel = "Qwen/Qwen-Image";
  final String _editModel = "Qwen/Qwen-Image-Edit";

  final String _defaultNegativePrompt = (
      "Simplified Chinese, deformed strokes, extra strokes, missing strokes, broken characters, "
          "typos, gibberish, illegible text, messy scribbles, distorted text, blurred text, "
          "worst quality, low resolution, bad anatomy, watermark, signature"
  );

  /// 根據場景參數生成懷舊影像
  Future<String?> generateNostalgicImage({
    required String scene,
    String text = "",
    String era = "historical",
    String location = "Taiwan",
  }) async {
    debugPrint("🔄 [生圖] 正在呼叫 API 生成圖片...");
    final String basePrompt = (
        "A nostalgic real photography from 1980s Taiwan, photorealistic, memory atmosphere, warm lighting. "
            "Detailed scene: $scene. "
    );

    final url = Uri.parse("$_baseUrl/images/generations");

    try {
      final response = await http.post(
          url,
          headers: {
            "Authorization": "Bearer ${ReminiCareConfig.siliconFlowApiKey}",
            "Content-Type": "application/json"
          },
          body: jsonEncode({
            "model": _generationModel,
            "prompt": basePrompt,
            "negative_prompt": _defaultNegativePrompt,
            "image_size": "1024x1024",
            "batch_size": 1
          })
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String cloudImageUrl = data['images'][0]['url'];
        return await _downloadAndSave(cloudImageUrl, prefix: "gen");
      } else {
        debugPrint("❌ [生圖失敗] API 異常代碼: ${response.statusCode}, 回傳內容: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ [生圖失敗] 連線錯誤: $e");
    }
    return null;
  }

  /// 直連 Qwen-Image-Edit 進行 Base64 改圖
  Future<String?> editImage({
    required String imagePath,
    required String editInstruction,
    int? seed,
  }) async {
    debugPrint("🔄 [改圖] 正在呼叫 API 修改圖片: '$editInstruction'...");

    if (kIsWeb) return null;

    final file = File(imagePath);
    if (!file.existsSync()) return null;

    try {
      final Uint8List imageBytes = await file.readAsBytes();
      final String encodedString = base64Encode(imageBytes);
      final String base64ImageData = "data:image/png;base64,$encodedString";

      final String editPrompt = (
          "A warm, nostalgic real photography from Taiwan. "
              "Based on the original image, $editInstruction. "
              "Keep the existing background untouched, ensure high quality."
      );

      final url = Uri.parse("$_baseUrl/images/generations");

      final Map<String, dynamic> payload = {
        "model": _editModel,
        "prompt": editPrompt,
        "negative_prompt": _defaultNegativePrompt,
        "image_size": "1024x1024",
        "image": base64ImageData
      };

      if (seed != null) {
        payload["seed"] = seed;
      }

      final response = await http.post(
          url,
          headers: {
            "Authorization": "Bearer ${ReminiCareConfig.siliconFlowApiKey}",
            "Content-Type": "application/json"
          },
          body: jsonEncode(payload)
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String cloudImageUrl = data['images'][0]['url'];
        return await _downloadAndSave(cloudImageUrl, prefix: "edit");
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
