import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:openai_dart/openai_dart.dart';
import 'package:remini_care_ai_app/services/prompts.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

// ==========================================
// NVIDIA LLM 服務 (對話生成與關鍵字萃取)
// ==========================================
class NvidiaLlmService {
  final String _baseApiUrl = "https://integrate.api.nvidia.com/v1";
  final String _model = "qwen/qwen3-next-80b-a3b-instruct";

  OpenAIClient get _client {
    final baseUrl = kIsWeb ? "https://corsproxy.io/?$_baseApiUrl" : _baseApiUrl;
    return OpenAIClient(
      config: OpenAIConfig(
        authProvider: ApiKeyProvider(ReminiCareConfig.nvidiaApiKey),
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 10),
      ),
    );
  }

  Future<String> generateInitialQuestion() async {
    try {
      final response = await _client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: _model,
          temperature: 0.9,
          maxTokens: 50,
          messages: [
            ChatMessage.system(INITIAL_QUESTION_PROMPT),
            ChatMessage.user("請隨機挑選一個全新的懷舊主題來問我。(隨機碼：${DateTime.now().millisecondsSinceEpoch})"),
          ],
        ),
      );

      print("[NVIDIA] 初始隨機出題成功！");
      final String text = response.text ?? '';
      return text.trim().isNotEmpty ? text.trim() : "哈囉！小時候家裡最常吃什麼呢？";

    } catch (e) {
      print("[NVIDIA] 初始出題發生錯誤: $e");
      return "哈囉！小時候家裡最常吃什麼呢？";
    }
  }

  /// 產生與長輩的陪伴溫慢對話
  Future<String> generateChatReply(String userMessage, List<Map<String, String>> history) async {
    try {
      List<ChatMessage> messages = [
        ChatMessage.system(CHATBOT_SYSTEM_PROMPT),
      ];

      for (var msg in history) {
        final role = msg['role'];
        final content = msg['content'] ?? '';

        if (role == 'user') {
          messages.add(ChatMessage.user(content));
        } else if (role == 'assistant') {
          messages.add(ChatMessage.assistant(content: content));
        }
      }

      messages.add(ChatMessage.user(userMessage));

      final response = await _client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: _model,
          temperature: 0.6,
          maxTokens: 150,
          messages: messages,
        ),
      );

      final String text = response.text ?? '';
      return text.trim().isNotEmpty ? text.trim() : "阿公阿嬤拍謝，我這邊稍微聽不清楚，您可以再說一次嗎？";

    } catch (e) {
      print("[NVIDIA] 陪伴對話錯誤: $e");
      return "阿公阿嬤拍謝，我這邊稍微聽不清楚，您可以再說一次嗎？";
    }
  }

  /// 從逐字稿中精準抓取 1~5 個視覺關鍵字
  Future<List<String>> extractKeywords(String transcript) async {
    try {
      final response = await _client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: _model,
          temperature: 0.1,
          messages: [
            ChatMessage.system(EXTRACTOR_SYSTEM_PROMPT),
            ChatMessage.user(transcript),
          ],
        ),
      );

      String rawOutput = (response.text ?? '').trim();

      if (rawOutput.startsWith("```json")) {
        rawOutput = rawOutput.replaceAll("```json", "").replaceAll("```", "").trim();
      } else if (rawOutput.startsWith("```")) {
        rawOutput = rawOutput.replaceAll("```", "").trim();
      }

      final List<dynamic> decoded = jsonDecode(rawOutput);
      return decoded.map((e) => e.toString()).toList();

    } catch (e) {
      print("[NVIDIA] 關鍵字擷取錯誤: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> extractSceneData(String transcript) async {
    final Map<String, dynamic> defaultResult = {
      "scene": "台灣早期懷舊生活場景",
      "era": "1980s",
      "location": "Taiwan",
      "keywords": <String>[]
    };

    try {
      final response = await _client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: _model,
          temperature: 0.1,
          messages: [
            ChatMessage.system(EXTRACTOR_SYSTEM_PROMPT),
            ChatMessage.user(transcript),
          ],
        ),
      );

      String rawOutput = (response.text ?? '').trim();

      if (rawOutput.startsWith("```json")) {
        rawOutput = rawOutput.replaceAll("```json", "").replaceAll("```", "").trim();
      } else if (rawOutput.startsWith("```")) {
        rawOutput = rawOutput.replaceAll("```", "").trim();
      }

      // 💡 防呆檢查：判斷 LLM 回傳的是 Array 還是 Map
      final dynamic decoded = jsonDecode(rawOutput);

      if (decoded is List) {
        debugPrint("[NVIDIA] 警告: LLM 回傳了陣列而非物件，已自動容錯處理。");
        return {
          "scene": "台灣早期懷舊生活場景",
          "era": "1980s",
          "location": "Taiwan",
          "keywords": decoded.map((e) => e.toString()).toList()
        };
      } else if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        return defaultResult;
      }

    } catch (e) {
      print("[NVIDIA] 場景擷取錯誤: $e");
    }
    return defaultResult;
  }

  Future<List<String>> recommendationSongsName(String? language) async {
    try {
      final response = await _client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: _model,
          temperature: 0.9,
          maxTokens: 1000,
          messages: [
            ChatMessage.system(SONG_RECOMMENDATION_PROMPT.replaceAll("\$language", language ?? "國語")),
            ChatMessage.user("請挑選十首老歌的歌名給我。(隨機碼：${DateTime.now().millisecondsSinceEpoch})"),
          ],
        ),
      );

      String rawOutput = (response.text ?? '').trim();

      if (rawOutput.startsWith("```json")) {
        rawOutput = rawOutput.replaceAll("```json", "").replaceAll("```", "").trim();
      } else if (rawOutput.startsWith("```")) {
        rawOutput = rawOutput.replaceAll("```", "").trim();
      }

      try {
        final List<dynamic> decoded = jsonDecode(rawOutput);
        return decoded.map((e) => e.toString()).toList();
      } catch (e) {
        print("[NVIDIA] JSON 解析失敗，LLM 回傳的原始字串為: $rawOutput");
        return [];
      }

    } catch(e) {
      print("[NVIDIA] 歌曲推薦錯誤: $e");
      return [];
    }
  }
}