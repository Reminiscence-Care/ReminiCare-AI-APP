import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 引入本地資料持久化套件

// =========================================================================
// 💡 設定欄位元數據模型，用於動態生成 UI 與自動儲存
// =========================================================================
class ConfigField {
  final String apiKey;       // 用於 SharedPreferences 與 .env 中的鍵值 (例如: NVIDIA_API_KEY)
  final String displayName;  // 顯示在設定彈窗中的標題 (例如: NVIDIA API KEY)
  final String hintText;     // 文字框內的預留提示字 (例如: nvapi-...)

  const ConfigField({
    required this.apiKey,
    required this.displayName,
    required this.hintText,
  });
}

// =========================================================================
// 🔑 ReminiCare AI 全域金鑰配置區 (完全宣告式動態配置引擎)
// =========================================================================
class ReminiCareConfig {
  // 1. 記憶體金鑰快取 (一律使用 Map 進行動態管理)
  static final Map<String, String> _configs = {};

  // 💡 2. 宣告式配置清單：未來要新增任何金鑰，只需在這裡加一行，首頁 UI 與儲存邏輯將自動同步建置！
  static final List<ConfigField> fields = [
    const ConfigField(
        apiKey: 'NVIDIA_API_KEY',
        displayName: 'NVIDIA API KEY (語言模型)',
        hintText: 'nvapi-...'
    ),
    const ConfigField(
        apiKey: 'GROQ_API_KEY',
        displayName: 'GROQ API KEY (備用 STT)',
        hintText: 'gsk_...'
    ),
    const ConfigField(
        apiKey: 'SILICONFLOW_API_KEY',
        displayName: 'SILICONFLOW KEY (影像生成)',
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
  ];

  // 3. 保留核心 Getters 以完美向下相容
  static String get nvidiaApiKey => _configs['NVIDIA_API_KEY'] ?? "";
  static String get groqApiKey => _configs['GROQ_API_KEY'] ?? "";
  static String get siliconFlowApiKey => _configs['SILICONFLOW_API_KEY'] ?? "";
  static String get nckuTtsToken => _configs['NCKU_TTS_TOKEN'] ?? "";
  static String get nckuSttToken => _configs['NCKU_STT_TOKEN'] ?? "";

  /// 提供外界依據 key 動態取得金鑰的接口
  static String getValue(String apiKey) => _configs[apiKey] ?? "";

  /// 🔄 一、動態加載金鑰：優先讀取使用者手動在 UI 輸入的金鑰，若無則讀取本地 .env 檔案
  static Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. 動態從 SharedPreferences 本機資料庫讀取所有已定義的金鑰
      for (var field in fields) {
        _configs[field.apiKey] = prefs.getString(field.apiKey) ?? "";
      }

      debugPrint("[金鑰管理] 動態加載手機本地快取金鑰完成。");

      // 2. 如果發現還有尚未配置的金鑰，且處於開發測試環境，則動態解析本地 .env 檔案
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

              // 僅在 Map 中包含該 key，且使用者尚未手動覆蓋時才載入
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

  /// 💾 二、動態儲存金鑰：接收動態 Map 鍵值對，一次性永久儲存至 SharedPreferences
  static Future<void> saveConfig(Map<String, String> newConfigs) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 動態循環寫入 SharedPreferences
      for (var entry in newConfigs.entries) {
        final String key = entry.key;
        final String val = entry.value.trim();

        _configs[key] = val; // 更新記憶體快取
        await prefs.setString(key, val);
      }

      debugPrint("[金鑰管理] 新金鑰已成功永久儲存至 SharedPreferences 本地資料庫！");
    } catch (e) {
      debugPrint("[金鑰管理] 儲存金鑰至 SharedPreferences 失敗: $e");
    }
  }
}

// ==========================================
// 🧠 集中管理 System Prompts
// ==========================================
const String CHATBOT_SYSTEM_PROMPT = """
# Role
你是一位溫和、有耐心且充滿親切感的「長輩回憶傾聽者」。你的任務是引導台灣的長輩分享他們過去的故事，並給予充滿同理心的回應。

# Tone & Style
- 語氣必須溫和、尊重，像是在跟自己的阿公阿嬤聊天。
- 句子必須「極度簡短、口語化」，每次回覆控制在 2 到 3 句話以內。
- 絕對不要使用任何 AI 術語、專業詞彙或複雜的邏輯推演。
- 適當加入台灣長輩熟悉的在地詞彙（如：古早味、灶腳、阿母、厝邊），讓對話更具親切感。

# Task Guidelines
1. 【分享回憶時】：先熱情肯定長輩的分享，接著針對細節提出一個簡單的感官問題（例如味道、感覺），引導具體畫面。
2. 【長輩說圖片「哪裡不對」時】：溫柔地接受指正，並用一句話向長輩確認你要修改的地方。
3. 【長輩覺得圖片「像」並延伸話題時】：表達驚喜與共鳴，並鼓勵他們繼續順著這個回憶往下說。

# Restrictions
- 嚴禁條列式或長篇大論的回覆。
""";

const String EXTRACTOR_SYSTEM_PROMPT = """
# Role
你是一個精準的「視覺關鍵字擷取系統」。你的任務是分析長輩的回憶對話逐字稿，並從中萃取出具體、可視覺化的核心物件或場景，轉換為結構化的 JSON 格式。

# Task Guidelines
1. 分析輸入的逐字稿，提取出 1 到 5 個最具代表性的「視覺化名詞」或「簡短名詞片語」。
2. 排除所有情緒詞、動詞、連接詞與無意義的發語詞。
3. 如果使用者是在進行「修改（哪裡不對）」，請特別抓出使用者強調要新增或替換的具體物件。
4. 輸出的字詞必須極度精煉，適合送給生圖 AI。

# Output Format
必須推導嚴格輸出為 JSON 陣列格式，例如 ["灶腳", "蕃薯飯", "滷豆乾"]。
絕對不要包含任何 Markdown 標記（如 ```json）、解釋說明或其他多餘文字。
""";

const String INITIAL_QUESTION_PROMPT = """
# Role
你是一位溫慢、有耐心且充滿親切感的「長輩回憶傾聽者」。

# Task
請隨機生成「一句」簡短、口語化且充滿台灣在地懷舊感的問題，用來當作與長輩聊天的開場白。
話題可以隨機圍繞在：小時候的童玩、以前的年夜飯、過去的灶腳、年輕時的約會、家鄉的風景、或是以前的零嘴。

# Restrictions
- 只能輸出一句話，字數盡量控制在 15 到 20 字以內。
- 絕對不要加引號、問候語或任何多餘的解釋。
- 語氣要像對自己的阿公阿嬤說話（例如：阿公，以前小時候都玩些什麼遊戲呀？）。
""";

// ==========================================
// 🔌 獨立 AI 服務直連客戶端
// ==========================================

/// 1. NVIDIA LLM 服務 (對話生成與關鍵字萃取)
class NvidiaLlmService {
  final String _rawUrl = "https://integrate.api.nvidia.com/v1/chat/completions";
  final String _model = "meta/llama-3.1-8b-instruct";

  String get _url => kIsWeb ? "https://corsproxy.io/?$_rawUrl" : _rawUrl;

  /// 隨機產生開場白懷舊問題
  Future<String> generateInitialQuestion() async {
    try {
      final response = await http.post(
          Uri.parse(_url),
          headers: {
            "Authorization": "Bearer ${ReminiCareConfig.nvidiaApiKey}",
            "Content-Type": "application/json"
          },
          body: jsonEncode({
            "model": _model,
            "messages": [
              {"role": "user", "content": INITIAL_QUESTION_PROMPT}
            ],
            "temperature": 0.8,
            "max_tokens": 50
          })
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        print("[NVIDIA] 初始出題成功！");
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        debugPrint("[NVIDIA] 初始出題失敗。狀態碼: ${response.statusCode}");
        debugPrint("[NVIDIA] 錯誤詳情: ${response.body}");
      }
    } catch (e) {
      debugPrint("[NVIDIA] 初始出題程式碼層發生錯誤: $e");
    }
    return "哈囉！小時候家裡最常吃什麼呢？";
  }

  /// 產生與長輩的陪伴溫慢對話
  Future<String> generateChatReply(String userMessage, List<Map<String, String>> history) async {
    try {
      final messages = [
        {"role": "system", "content": CHATBOT_SYSTEM_PROMPT},
        ...history,
        {"role": "user", "content": userMessage}
      ];

      final response = await http.post(
          Uri.parse(_url),
          headers: {
            "Authorization": "Bearer ${ReminiCareConfig.nvidiaApiKey}",
            "Content-Type": "application/json"
          },
          body: jsonEncode({
            "model": _model,
            "messages": messages,
            "temperature": 0.6,
            "max_tokens": 150
          })
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        print("[NVIDIA] 對話回覆失敗。狀態碼: ${response.statusCode}");
        print("[NVIDIA] 錯誤詳情: ${response.body}");
      }
    } catch (e) {
      print("[NVIDIA] 陪伴對話錯誤: $e");
    }
    return "阿公阿嬤拍謝，我這邊稍微聽不清楚，您可以再說一次嗎？";
  }

  /// 從逐字稿中精準抓取 1~5 個視覺關鍵字
  Future<List<String>> extractKeywords(String transcript) async {
    try {
      final response = await http.post(
          Uri.parse(_url),
          headers: {
            "Authorization": "Bearer ${ReminiCareConfig.nvidiaApiKey}",
            "Content-Type": "application/json"
          },
          body: jsonEncode({
            "model": _model,
            "messages": [
              {"role": "system", "content": EXTRACTOR_SYSTEM_PROMPT},
              {"role": "user", "content": transcript}
            ],
            "temperature": 0.1
          })
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String rawOutput = data['choices'][0]['message']['content'].toString().trim();

        if (rawOutput.startsWith("```json")) {
          rawOutput = rawOutput.replaceAll("```json", "").replaceAll("```", "").trim();
        } else if (rawOutput.startsWith("```")) {
          rawOutput = rawOutput.replaceAll("```", "").trim();
        }

        final List<dynamic> decoded = jsonDecode(rawOutput);
        return decoded.map((e) => e.toString()).toList();
      } else {
        print("[NVIDIA] 關鍵字擷取失敗。狀態碼: ${response.statusCode}");
        print("[NVIDIA] 錯誤詳情: ${response.body}");
      }
    } catch (e) {
      print("[NVIDIA] 關鍵字擷取錯誤: $e");
    }
    return [];
  }
}

/// 2. Groq Whisper 語音辨識服務 (STT - 作為本地開發備用)
class GroqSttService {
  final String _rawUrl = "https://api.groq.com/openai/v1/audio/transcriptions";

  // Web CORS 自動中轉
  String get _url => kIsWeb ? "https://corsproxy.io/?$_rawUrl" : _rawUrl;

  Future<String?> transcribe(String audioFilePath) async {
    if (kIsWeb) return null;
    try {
      final file = File(audioFilePath);
      if (!file.existsSync()) return null;

      final request = http.MultipartRequest('POST', Uri.parse(_url));
      request.headers['Authorization'] = 'Bearer ${ReminiCareConfig.groqApiKey}';
      request.fields['model'] = 'whisper-large-v3';
      request.fields['language'] = 'zh';
      request.fields['prompt'] = '這是一段台灣長輩的對話，包含中文與台語，請輸出繁體中文。';
      request.fields['response_format'] = 'json';

      request.files.add(await http.MultipartFile.fromPath('file', audioFilePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['text'].toString().trim();
      }
    } catch (e) {
      debugPrint("[Groq STT] 辨識出錯: $e");
    }
    return null;
  }
}

/// 3. SiliconFlow 影像生成與修改服務 (Text-to-Image / Image-to-Image)
class SiliconFlowImageService {
  final String _rawBaseUrl = "https://api.siliconflow.com/v1";

  // Web CORS 自動中轉
  String get _baseUrl => kIsWeb ? "https://corsproxy.io/?$_rawBaseUrl" : _rawBaseUrl;

  final String _generationModel = "Qwen/Qwen-Image";
  final String _editModel = "Qwen/Qwen-Image-Edit";

  final String _defaultNegativePrompt = (
      "Simplified Chinese, deformed strokes, extra strokes, missing strokes, broken characters, "
          "typos, gibberish, illegible text, messy scribbles, distorted text, blurred text, "
          "worst quality, low resolution, bad anatomy, watermark, signature"
  );

  /// 一、根據場景參數生成懷舊影像
  Future<String?> generateNostalgicImage({
    required String scene,
    String text = "",
    String era = "historical",
    String location = "Taiwan",
  }) async {
    debugPrint("🔄 [生圖] 正在呼叫 API 生成圖片...");
    debugPrint(" ├─ [設定] 年代: $era | 地點: $location");
    debugPrint(" ├─ [設定] 場景: $scene");
    debugPrint(" └─ [設定] 文字: ${text.isNotEmpty ? text : '(無要求)'}");

    final String basePrompt = (
        "A documentary-style historical photograph of $location in the $era. "
            "Style: Retro film camera, nostalgic atmosphere, authentic Taiwanese local street vibe, slightly faded warm colors. "
            "Scene: $scene. "
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

  /// 二、直連 Qwen-Image-Edit 進行 Base64 改圖
  Future<String?> editImage({
    required String imagePath,
    required String editInstruction,
    int? seed,
  }) async {
    debugPrint("🔄 [改圖] 正在呼叫 API 修改圖片: '$editInstruction'...");

    if (kIsWeb) {
      debugPrint("❌ [改圖失敗] Web 瀏覽器環境因沙盒限制無法直接讀取本地檔案。");
      return null;
    }

    final file = File(imagePath);
    if (!file.existsSync()) {
      debugPrint("❌ [改圖失敗] 找不到原圖文件: $imagePath");
      return null;
    }

    try {
      final Uint8List imageBytes = await file.readAsBytes();
      final String encodedString = base64Encode(imageBytes);
      final String base64ImageData = "data:image/png;base64,$encodedString";

      final String editPrompt = (
          "A warm, nostalgic real photography from Taiwan. "
              "Based on the original image, $editInstruction. "
              "Keep the existing background, text, and atmosphere untouched, ensure high quality."
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
      } else {
        debugPrint("❌ [改圖失敗] API 異常代碼: ${response.statusCode}, 回傳內容: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ [改圖失敗] 連線與轉換錯誤: $e");
    }
    return null;
  }

  /// 三、共用的圖片下載與儲存邏輯 (解決 Web 平台 CORS 下載與儲存)
  Future<String?> _downloadAndSave(String imageUrl, {required String prefix}) async {
    try {
      final downloadUrl = kIsWeb ? "https://corsproxy.io/?$imageUrl" : imageUrl;
      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode == 200) {
        if (kIsWeb) {
          return imageUrl;
        }

        final directory = await getTemporaryDirectory();
        final String outputFilename = "${prefix}_${DateTime.now().millisecondsSinceEpoch}.png";
        final String outputPath = "${directory.path}/$outputFilename";

        final file = File(outputPath);
        await file.writeAsBytes(response.bodyBytes);

        debugPrint("✅ 圖片本地緩存處理成功！儲存路徑: $outputPath");
        return outputPath;
      }
    } catch (e) {
      debugPrint("❌ 圖片本地儲存下載失敗: $e");
    }
    return imageUrl;
  }
}

// =========================================================================
// 💡 4. 成大自研語音與音訊整合服務 (100% 完美接合 NCKU ASR & VITS TCP-TTS 原始架構)
// =========================================================================
class NckuSpeechService {
  // 1. TTS 連線設定 (VITS-TCP_server Port 9998)
  final String _ttsHost = '140.116.245.146';
  final int _ttsPort = 9998;
  final String _ttsEndOfTransmission = 'EOT';
  final String _ttsApiId = '10012';

  // 2. ASR REST API 連線設定 (Port 5002 proxy)
  final String _sttUrl = 'http://140.116.245.149:5002/proxy';

  // ==========================================
  // 🎙️ 一、成大自研語音辨識服務 (100% 同步 ASR Form-Encoded 規格)
  // ==========================================
  Future<String?> transcribe(String audioFilePath) async {
    if (kIsWeb) {
      debugPrint("[NCKU STT] 瀏覽器 Web 安全限制不支援直接檔案讀取。");
      return null;
    }
    try {
      debugPrint("[NCKU STT] 讀取音檔: $audioFilePath");
      final file = File(audioFilePath);
      if (!await file.exists()) {
        debugPrint("[NCKU STT] ❌ 音檔不存在");
        return null;
      }

      final List<int> fileBytes = await file.readAsBytes();
      debugPrint("[NCKU STT] 音檔大小: ${fileBytes.length} bytes");

      final String base64Audio = base64Encode(fileBytes);

      // 💡 ASR 規定：使用 form-encoded 格式進行 Post 傳輸
      final Map<String, String> data = {
        "lang": "Chinese & Taiwanese", // 中文與台語辨識輸出繁體中文
        "token": ReminiCareConfig.nckuSttToken, // 💡 採用獨立動態設定的 NCKU_STT_TOKEN
        "audio": base64Audio,
      };

      debugPrint("[NCKU STT] POST → $_sttUrl");
      final response = await http
          .post(Uri.parse(_sttUrl), body: data)
          .timeout(const Duration(seconds: 60)); // 最多等 60 秒防 UI 鎖死

      debugPrint("[NCKU STT] 回應 status=${response.statusCode}");

      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final String? sentence = body["sentence"] as String?;

        if (sentence == null || sentence == "<{silent}>") {
          debugPrint("[NCKU STT] 偵測為靜音");
          return null;
        }

        final String trimmedSentence = sentence.trim();
        debugPrint("[NCKU STT] 辨識成功: '$trimmedSentence'");
        return trimmedSentence;
      } else {
        debugPrint("[NCKU STT] ❌ 請求失敗: ${response.statusCode} body=${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("[NCKU STT] ❌ ASR 連線與解析出錯: $e");
      return null;
    }
  }

  // ==========================================
  // 🔊 二、成大自研語音合成服務 (100% 同步 Port 9998 VITS-TCP 協定)
  // ==========================================
  Future<Uint8List?> generateSpeech(String text, String language) async {
    if (kIsWeb) {
      debugPrint("[NCKU TTS] 瀏覽器 Web 安全限制不支援直接通訊。");
      return null;
    }
    if (text.isEmpty) {
      debugPrint("[NCKU TTS] ❌ 傳入的文字不能為空");
      return null;
    }
    if (text.contains('@@@')) {
      debugPrint("[NCKU TTS] ❌ 傳入的文字不能含有分隔符 '@@@'");
      return null;
    }

    // 💡 規格映射：語言代碼（zh / tw）、推薦語者、Token
    final String langCode = (language == "台語") ? "tw" : "zh";
    final String speaker = (language == "台語") ? "M04" : "4793"; // 台語推薦阿母 M04，國語推薦預設男生 4793
    final String token = ReminiCareConfig.nckuTtsToken;

    debugPrint("[NCKU TTS] 正在建立與 VITS-TCP Server 的連線: $_ttsHost:$_ttsPort");

    try {
      final Socket socket = await Socket.connect(_ttsHost, _ttsPort, timeout: const Duration(seconds: 5));

      // 💡 規格組裝：apiId@@@token@@@language@@@speaker@@@dataEOT
      final String message = "$_ttsApiId@@@$token@@@$langCode@@@$speaker@@@$text$_ttsEndOfTransmission";

      socket.add(utf8.encode(message));
      await socket.flush();

      final List<int> responseBytes = [];
      final Completer<Uint8List?> completer = Completer<Uint8List?>();

      // 💡 異步接聽 TCP Socket 回傳的 JSON 切片位元組
      socket.listen(
            (chunk) => responseBytes.addAll(chunk),
        onDone: () {
          try {
            final String resultString = utf8.decode(responseBytes);
            if (resultString.isEmpty) {
              completer.complete(null);
              return;
            }

            final Map<String, dynamic> response = jsonDecode(resultString) as Map<String, dynamic>;

            if (response["status"] == true) {
              // 💡 動態讀取 Base64 合成音軌並解碼為 PCM/WAV 位元組
              final String base64Wav = response["bytes"] ?? "";
              final Uint8List wavBytes = base64Decode(base64Wav);

              debugPrint("✅ [NCKU TTS 成功] 語音合成流加載完成。格式: WAV");
              completer.complete(wavBytes);
            } else {
              final String error = response["message"] ?? response["Message"] ?? "Unknown Error";
              debugPrint("❌ [NCKU TTS 伺服器錯誤]: $error");
              completer.complete(null);
            }
          } catch (e) {
            completer.completeError(e);
          }
        },
        onError: (e) => completer.completeError(e),
        cancelOnError: true,
      );

      // 等待最長 60 秒接收排隊佇列
      final Uint8List? audioData = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('成大 TTS 伺服器接收超時'),
      );

      await socket.close();
      socket.destroy();

      return audioData;

    } catch (e) {
      debugPrint("❌ [NCKU TTS 致命錯誤]: $e");
      return null;
    }
  }
}