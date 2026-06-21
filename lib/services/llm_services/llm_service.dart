import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:openai_dart/openai_dart.dart';
import 'package:remini_care_ai_app/services/llm_services/prompts.dart';
import 'package:remini_care_ai_app/services/api_services.dart';

class LlmService implements ILLMService {
  final String baseUrl;
  final String model;
  final String apiKey;

  LlmService({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  String get modelName {
    return model;
  }

  OpenAIClient get _client {
    final finalBaseUrl = kIsWeb ? "https://corsproxy.io/?$baseUrl" : baseUrl;
    return OpenAIClient(
      config: OpenAIConfig(
        authProvider: ApiKeyProvider(apiKey),
        baseUrl: finalBaseUrl,
        timeout: const Duration(seconds: 10),
      ),
    );
  }

  /// 泛用的請求 Function，整合歷史紀錄、角色設定與錯誤處理
  Future<String> request(
      String? systemPrompt,
      String userPrompt,
      List<Map<String, String>> history, {
        double temperature = 0.6,
        int maxTokens = 150,
      }) async {
    try {
      List<ChatMessage> messages = [];
      if (systemPrompt != null) {
        messages.add(ChatMessage.system(systemPrompt));
      }

      for (var msg in history) {
        final role = msg['role'];
        final content = msg['content'] ?? '';
        if (role == 'user') {
          messages.add(ChatMessage.user(content));
        } else if (role == 'assistant') {
          messages.add(ChatMessage.assistant(content: content));
        }
      }

      messages.add(ChatMessage.user(userPrompt));

      final response = await _client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: model,
          temperature: temperature,
          maxTokens: maxTokens,
          messages: messages,
        ),
      );

      final String text = (response.text ?? '').trim();
      return text.isNotEmpty ? text : "";
    } catch (e) {
      debugPrint("[LLM ERROR] $e");
      return "[ERROR]";
    }
  }

  /// 輔助：移除 Markdown 的 JSON 區塊標記
  String _cleanJson(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith("```json")) {
      cleaned = cleaned.replaceAll("```json", "").replaceAll("```", "").trim();
    } else if (cleaned.startsWith("```")) {
      cleaned = cleaned.replaceAll("```", "").trim();
    }
    return cleaned;
  }

  /// 產生初始隨機懷舊問題
  Future<String> generateInitialQuestion() async {
    final response = await request(
      INITIAL_QUESTION_PROMPT,
      "請隨機挑選一個全新的懷舊主題來問我。(隨機碼：${DateTime.now().millisecondsSinceEpoch})",
      [],
      temperature: 0.9,
      maxTokens: 50,
    );

    return (response == "[ERROR]" || response.isEmpty)
        ? "哈囉！小時候家裡最常吃什麼呢？"
        : response;
  }

  @override
  Future<String> generateChatReply(String userMessage, List<Map<String, String>> history) async {
    final response = await request(
      CHATBOT_SYSTEM_PROMPT,
      userMessage,
      history,
    );

    return (response == "[ERROR]" || response.isEmpty)
        ? "阿公阿嬤拍謝，我這邊稍微聽不清楚，您可以再說一次嗎？"
        : response;
  }

  @override
  Future<String> generateExtendedQuestion(String previousQuestion, String elderResponse) async {
    final response = await request(
      "你是一個親切的台灣早期懷舊引導助理。請根據先前的提問，以及長輩剛剛的回答，延伸出一個有溫度、口語化且具體的新問題，字數控制在 25 到 45 字以內。請直接回傳該新問題，不要附帶任何引號、前言、多餘問候或解釋。使用台灣繁體中文（可穿插親切的台語口吻助詞，例如『那那時...』『那那時候...』）。",
      "先前的提問：『$previousQuestion』\n長輩的回答：『$elderResponse』\n請產生一個延伸問題：",
      [],
      temperature: 0.8,
      maxTokens: 100,
    );

    return (response == "[ERROR]" || response.isEmpty)
        ? "這張照片有讓您想起更多小時候的趣味往事嗎？"
        : response;
  }

  @override
  Future<List<String>> extractKeywords(String transcript) async {
    final response = await request(EXTRACTOR_SYSTEM_PROMPT, transcript, [], temperature: 0.1);
    if (response == "[ERROR]" || response.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(_cleanJson(response));
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint("[LLM] 關鍵字擷取錯誤: $e");
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> extractSceneData(String transcript) async {
    final Map<String, dynamic> defaultResult = {
      "scene": "台灣早期懷舊生活場景",
      "era": "1980s",
      "location": "Taiwan",
      "keywords": <String>[]
    };

    final response = await request(EXTRACTOR_SYSTEM_PROMPT, transcript, [], temperature: 0.1);
    if (response == "[ERROR]" || response.isEmpty) return defaultResult;

    try {
      final dynamic decoded = jsonDecode(_cleanJson(response));
      if (decoded is List) {
        return {...defaultResult, "keywords": decoded.map((e) => e.toString()).toList()};
      } else if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint("[LLM] 場景擷取錯誤: $e");
    }
    return defaultResult;
  }

  @override
  Future<List<Map<String, String>>> recommendationSongsName(String? language) async {
    final response = await request(
      SONG_RECOMMENDATION_PROMPT.replaceAll("\$language", language ?? "國語"),
      "請挑選十首老歌的歌名及歌手名給我。(隨機碼:${DateTime.now().millisecondsSinceEpoch})",
      [],
      temperature: 0.9,
      maxTokens: 1000,
    );

    if (response == "[ERROR]" || response.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(_cleanJson(response));
      return decoded.map((item) => Map<String, String>.from(item as Map)).toList();
    } catch (e) {
      debugPrint("[LLM] JSON 解析失敗: $e");
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> getSingerAndSongNameFromQuery(String query) async {
    final response = await request(
      SONG_INFO_EXTRACTOR_PROMPT,
      "請告訴我根據以下資料，這首歌是哪位歌手的，以及歌名是甚麼。資料: $query",
      [],
      temperature: 0.1,
      maxTokens: 1000,
    );

    if (response == "[ERROR]" || response.isEmpty) return {};

    try {
      return jsonDecode(_cleanJson(response));
    } catch (e) {
      debugPrint("[LLM] JSON 解析失敗: $e");
      return {};
    }
  }

  @override
  Future<String> extractElderName(String text) async {
    final response = await request(
      NAME_EXTRACT_PROMPT,
      "請從這句擷取長輩名字或稱呼：$text",
      [],
      temperature: 0.1,
      maxTokens: 10,
    );

    return (response == "[ERROR]" || response.isEmpty) ? "無名氏" : response;
  }
}