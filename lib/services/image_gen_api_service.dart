import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:openai_dart/openai_dart.dart';

// ==========================================
// 💡 1. 統一的影像生成與修改介面 (Interface)
// ==========================================
abstract class IImageGenService {
  /// 根據場景、年代與地點生成懷舊影像
  Future<String?> generateNostalgicImage({
    required String scene,
    String text = "",
    String era = "1980s",
    String location = "Taiwan",
  });

  /// 根據使用者反饋對現有圖片進行修改
  Future<String?> editImage({
    required String imagePath,
    required String editInstruction,
    int? seed,
  });
}

// ==========================================
// 🧠 2. 基於 OpenAI 協議的共用核心 (Base Class)
// 將共用的 openai_dart 邏輯完美封裝，所有相容模型皆可繼承！
// ==========================================
abstract class BaseOpenAIImageService implements IImageGenService {
  final String Function() apiKeyProvider;
  final String? baseUrl;
  final String generationModel;

  BaseOpenAIImageService({
    required this.apiKeyProvider,
    required this.generationModel,
    this.baseUrl,
  });

  /// 動態實例化 OpenAIClient
  OpenAIClient get client {
    final String effectiveBaseUrl = baseUrl != null
        ? (kIsWeb ? "https://corsproxy.io" : baseUrl!)
        : "https://api.openai.com/v1";

    return OpenAIClient(
      config: OpenAIConfig(
        baseUrl: effectiveBaseUrl,
        authProvider: ApiKeyProvider(apiKeyProvider()),
        timeout: const Duration(seconds: 600), // 生圖時間較長，建議放寬至 45-60 秒
      ),
    );
  }

  /// 讓子類別可以擴充 Prompt
  String buildPrompt(String scene, String era, String location) {
    return "A nostalgic real photography from $era $location, photorealistic, memory atmosphere, warm lighting. "
        "Detailed scene: $scene.";
  }

  @override
  Future<String?> generateNostalgicImage({
    required String scene,
    String text = "",
    String era = "1980s",
    String location = "Taiwan",
  }) async {
    debugPrint("🔄 [ImageGen] 正在呼叫影像 API ($generationModel) 生成圖片...");
    final String finalPrompt = buildPrompt(scene, era, location);

    try {
      final response = await client.images.generate(
        ImageGenerationRequest(
          model: ImageModels.gptImage2,
          prompt: finalPrompt,
          n: 1,
          size: ImageSize.size1024x1024,
        ),
      );

      final imageResponse = response.data.first;

      // 🌟 核心修正：同時相容 Base64 與 URL 回傳格式
      if (imageResponse.b64Json != null && imageResponse.b64Json!.isNotEmpty) {
        debugPrint("⚡ [ImageGen] 收到 Base64 影像數據，直接進行本地快取儲存...");
        return await saveBase64Image(imageResponse.b64Json!, prefix: "gen");
      } else if (imageResponse.url != null && imageResponse.url!.isNotEmpty) {
        debugPrint("🌐 [ImageGen] 收到遠端圖片 URL，開始下載...");
        return await downloadAndSave(imageResponse.url!, prefix: "gen");
      }

    } catch (e) {
      debugPrint("❌ [生圖失敗]: $e");
    }
    return null;
  }

  /// 處理最新的 Base64 直接儲存，免去二次網路請求
  Future<String?> saveBase64Image(String base64String, {required String prefix}) async {
    try {
      final bytes = base64Decode(base64String);
      if (kIsWeb) {
        // Web 端無法直接操作 File System，直接回傳 Data URL 供 Image.network 或 Image.memory 渲染
        return "data:image/png;base64,$base64String";
      }

      final directory = await getTemporaryDirectory();
      final String outputPath = "${directory.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.png";
      final file = File(outputPath);
      await file.writeAsBytes(bytes);
      return outputPath;
    } catch (e) {
      debugPrint("❌ Base64 本地儲存失敗: $e");
    }
    return null;
  }

  /// 處理舊版模型或第三方相容端點的 URL 下載器
  Future<String?> downloadAndSave(String imageUrl, {required String prefix}) async {
    try {
      // 如果外層已經掛了 corsproxy 或者是自訂 baseUrl，imageUrl 有可能已經被處理過
      // 這裡維持原有的 Web 代理邏輯，但加上防重複判定
      final bool needsProxy = kIsWeb && !imageUrl.contains("corsproxy.io");
      final downloadUrl = needsProxy ? "https://corsproxy.io" : imageUrl;

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
// ==========================================
// 🎨 3. SiliconFlow 影像生成服務 (繼承自 Base Class)
// ==========================================
class SiliconFlowImageService extends BaseOpenAIImageService {
  final String? editModel;
  final String? defaultNegativePrompt;

  SiliconFlowImageService({
    required String rawBaseUrl,
    required super.apiKeyProvider,
    required super.generationModel,
    this.editModel,
    this.defaultNegativePrompt,
  }) : super(baseUrl: rawBaseUrl);

  /// 💡 擴充 Base Class 的 Prompt，將 SiliconFlow 專屬的負面提示詞塞入
  @override
  String buildPrompt(String scene, String era, String location) {
    String base = super.buildPrompt(scene, era, location);
    if (defaultNegativePrompt != null && defaultNegativePrompt!.isNotEmpty) {
      base += "\n\n(Avoid: $defaultNegativePrompt)";
    }
    return base;
  }

  @override
  Future<String?> editImage({
    required String imagePath,
    required String editInstruction,
    int? seed,
  }) async {
    if (editModel == null) return null;
    debugPrint("🔄 [SiliconFlow 改圖] 正在修改圖片: '$editInstruction'...");

    if (kIsWeb) return null;
    final file = File(imagePath);
    if (!file.existsSync()) return null;

    // 💡 注意：SiliconFlow 的改圖 API 是非標準的 Base64 傳輸 (而標準 OpenAI 需傳實體檔案+Mask)
    // 因此這裡我們必須保留原生的 HTTP Post 來處理它的特規 Payload
    try {
      final Uint8List imageBytes = await file.readAsBytes();
      final String encodedString = base64Encode(imageBytes);
      final String base64ImageData = "data:image/png;base64,$encodedString";

      final String editPrompt = "A warm, nostalgic real photography. Based on the original image, $editInstruction. Keep the existing background untouched, ensure high quality.";
      final String rawUrl = baseUrl ?? "https://api.siliconflow.com/v1";
      final url = Uri.parse("${kIsWeb ? 'https://corsproxy.io/?$rawUrl' : rawUrl}/images/generations");

      final Map<String, dynamic> payload = {
        "model": editModel,
        "prompt": editPrompt,
        "image": base64ImageData,
        "size": "1024x1024",
      };

      if (defaultNegativePrompt != null) payload["negative_prompt"] = defaultNegativePrompt;
      if (seed != null) payload["seed"] = seed;

      final response = await http.post(url, headers: { "Authorization": "Bearer ${apiKeyProvider()}", "Content-Type": "application/json" }, body: jsonEncode(payload));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String cloudImageUrl = (data['images'] != null && data['images'].isNotEmpty) ? data['images'][0]['url'] : (data['data'] != null ? data['data'][0]['url'] : "");
        if (cloudImageUrl.isNotEmpty) return await downloadAndSave(cloudImageUrl, prefix: "edit_sf");
      }
    } catch (e) {
      debugPrint("❌ [SiliconFlow 改圖失敗]: $e");
    }
    return null;
  }
}

// ==========================================
// 🎨 4. OpenAI DALL-E 3 原生影像服務 (繼承自 Base Class)
// ==========================================
class OpenAIImageService extends BaseOpenAIImageService {
  OpenAIImageService({required super.apiKeyProvider})
      : super(generationModel: 'dall-e-3');
  // 預設不傳 baseUrl，它會自動使用基底的 https://api.openai.com/v1

  @override
  Future<String?> editImage({
    required String imagePath,
    required String editInstruction,
    int? seed,
  }) async {
    // 💡 DALL-E 3 原生不支援直接的 createImageEdit (需 DALL-E 2 及特殊的 RGBA 透明遮罩)
    // 這裡我們進行「優雅降級」：將長輩的修改指令轉化為全新的生圖提示詞，重新產生圖片
    debugPrint("🔄 [OpenAI] DALL-E 3 重新生成 (優雅降級改圖): '$editInstruction'...");

    return await generateNostalgicImage(
      scene: "Based on previous memory, make this modification: $editInstruction.",
    );
  }
}