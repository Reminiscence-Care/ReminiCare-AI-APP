import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:remini_care_ai_app/services/prompts.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

// ==========================================
// 🧠 NVIDIA LLM 服務 (對話生成與關鍵字萃取)
// ==========================================
class NvidiaLlmService {
  final String _rawUrl = "https://integrate.api.nvidia.com/v1/chat/completions";
  final String _model = "qwen/qwen3-next-80b-a3b-instruct";

  String get _url => kIsWeb ? "https://corsproxy.io/?$_rawUrl" : _rawUrl;

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
              {"role": "system", "content": INITIAL_QUESTION_PROMPT},
              // 💡 傳入包含時間戳記的干擾碼，保證每次對話歷史都不同，打破 LLM 快取
              {"role": "user", "content": "請隨機挑選一個全新的懷舊主題來問我。(隨機碼：${DateTime.now().millisecondsSinceEpoch})"}
            ],
            "temperature": 0.9, // 💡 提高至 0.9，讓問題更發散
            "max_tokens": 50
          })
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        print("[NVIDIA] 初始隨機出題成功！");
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        debugPrint("[NVIDIA] 初始出題失敗。狀態碼: ${response.statusCode}");
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
      }
    } catch (e) {
      print("[NVIDIA] 關鍵字擷取錯誤: $e");
    }
    return [];
  }
}
