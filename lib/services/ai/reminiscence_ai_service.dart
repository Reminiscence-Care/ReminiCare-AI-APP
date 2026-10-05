import 'dart:math';

import '../../models/reminiscence_topic.dart';
import 'ai_service_exception.dart';
import 'ai_models.dart';
import 'llm_client.dart';
import 'provider_response_parser.dart';

class TopicRecommendationResult {
  const TopicRecommendationResult({
    required this.topics,
    this.usedFallback = false,
    this.warning,
  });

  final List<ReminiscenceTopic> topics;
  final bool usedFallback;
  final String? warning;
}

class ReminiscenceAiService {
  ReminiscenceAiService(this._client);
  final LlmClient _client;

  static const _fallbackTopics = <ReminiscenceTopic>[
    ReminiscenceTopic(
      title: '下棋',
      question: '以前大家都在哪裡下棋？有沒有常常一起玩的朋友？',
      followUpQuestion: '那時候最難忘的一盤棋，發生了什麼事？',
      imagePrompt:
          '1960s Taiwan, elderly friends playing Chinese chess under a banyan tree',
      imageSearchQuery: '台灣 樹下 下象棋 老照片 | vintage Taiwan Chinese chess',
      categoryId: 'childhood_games',
    ),
    ReminiscenceTopic(
      title: '歌仔戲',
      question: '以前看歌仔戲時，最喜歡哪一齣或哪一位演員？',
      followUpQuestion: '看戲那天通常會和誰一起去？現場熱鬧嗎？',
      imagePrompt:
          'traditional Taiwanese opera stage in a village temple square, 1970s',
      imageSearchQuery: '台灣 歌仔戲 戲台 老照片 | vintage Taiwanese opera stage',
      categoryId: 'entertainment',
    ),
    ReminiscenceTopic(
      title: '菜市場',
      question: '以前去菜市場，最常買什麼？有熟悉的攤販嗎？',
      followUpQuestion: '市場裡有什麼聲音或味道，現在還記得？',
      imagePrompt:
          'busy traditional Taiwan wet market in the 1970s, warm documentary photo',
      imageSearchQuery: '台灣 傳統菜市場 老照片 | vintage Taiwan wet market',
      categoryId: 'market',
    ),
    ReminiscenceTopic(
      title: '節日',
      question: '以前過年過節，家裡都會準備哪些事情？',
      followUpQuestion: '哪一個節日回憶讓大家最開心？',
      imagePrompt:
          'Taiwanese family celebrating a traditional festival in the 1960s',
      imageSearchQuery: '台灣 傳統節慶 老照片 | vintage Taiwan traditional festival',
      categoryId: 'festivals',
    ),
    ReminiscenceTopic(
      title: '上學',
      question: '以前上學要走多遠？同學之間都玩些什麼？',
      followUpQuestion: '還記得最疼愛你們的老師嗎？',
      imagePrompt:
          'Taiwan elementary school children walking to school in the 1960s',
      imageSearchQuery: '台灣 小學生 上學 老照片 | vintage Taiwan school children',
      categoryId: 'school_life',
    ),
    ReminiscenceTopic(
      title: '童年點心',
      question: '小時候最期待吃到什麼點心？通常在哪裡買？',
      followUpQuestion: '那個味道讓你想到哪一位家人？',
      imagePrompt:
          'nostalgic Taiwanese childhood snacks at an old grocery shop, 1970s',
      imageSearchQuery: '台灣 古早味 零食 雜貨店 | vintage Taiwan grocery snacks',
      categoryId: 'traditional_food',
    ),
    ReminiscenceTopic(
      title: '搭火車',
      question: '第一次搭火車去了哪裡？沿途看到了什麼？',
      followUpQuestion: '那次旅程是和誰一起去的？',
      imagePrompt:
          'old Taiwan railway station and train journey, 1960s documentary photograph',
      imageSearchQuery: '台灣 老火車站 老照片 | vintage Taiwan railway station',
      categoryId: 'railway',
    ),
    ReminiscenceTopic(
      title: '農忙',
      question: '以前農忙時，全家人會怎麼分工？',
      followUpQuestion: '忙完以後，大家會怎麼休息或慶祝？',
      imagePrompt:
          'Taiwan rice harvest with a family working together in the 1960s',
      imageSearchQuery: '台灣 稻田 農忙 收割 老照片 | vintage Taiwan rice harvest',
      categoryId: 'farming',
    ),
  ];

  Future<List<ReminiscenceTopic>> recommendTopics() async =>
      (await recommendTopicsWithStatus()).topics;

  Future<TopicRecommendationResult> recommendTopicsWithStatus() async {
    try {
      final raw = await _client.complete(
        messages: const [
          LlmMessage('system', '你是熟悉台灣長輩生活史的回憶治療引導員。只輸出合法 JSON，不要 markdown。'),
          LlmMessage(
            'user',
            '''產生四個互不重複、容易讓多位長輩一起聊天的台灣懷舊主題。回傳 {"topics":[...]}，每項只能有 title、question、followUpQuestion、imagePrompt、imageSearchQuery、categoryId。categoryId 必須選自 childhood_games、school_life、traditional_food、market、farming、railway、festivals、family、work、neighborhood、entertainment。title 使用 2-6 個繁體中文字，避免「舊時生活」「懷舊時光」等抽象題目。問題使用台灣繁體中文；imagePrompt 必須描述畫面中可見的主要人物、動作與物件；imageSearchQuery 格式為「具體繁體中文搜尋詞 | specific English search terms」，不可只用記憶、生活、懷舊等抽象詞，必須包含可見的主要物件或活動、Taiwan 與年代或 vintage。''',
          ),
        ],
        temperature: 0.35,
        maxTokens: 4096,
        jsonObject: true,
      );
      final decoded = decodeJsonObjectFromText(raw, requiredKey: 'topics');
      final topicList = decoded['topics'];
      if (topicList is! List) {
        throw const FormatException('topics is not a list');
      }
      final topics = topicList
          .whereType<Map<String, dynamic>>()
          .map(ReminiscenceTopic.fromJson)
          .where(_isComplete)
          .toList();
      if (topics.length != 4 ||
          topics.map((e) => e.title).toSet().length != 4 ||
          topics.map((e) => e.categoryId).toSet().length != 4) {
        throw const FormatException(
          'topics must contain four unique titles and categories',
        );
      }
      return TopicRecommendationResult(topics: topics);
    } on AiServiceException catch (error) {
      return TopicRecommendationResult(
        topics: fallbackTopics(),
        usedFallback: true,
        warning: error.message,
      );
    } on FormatException catch (error) {
      return TopicRecommendationResult(
        topics: fallbackTopics(),
        usedFallback: true,
        warning: 'LLM 回傳的主題格式不正確：${error.message}',
      );
    } catch (error) {
      return TopicRecommendationResult(
        topics: fallbackTopics(),
        usedFallback: true,
        warning: 'LLM 主題生成失敗：$error',
      );
    }
  }

  List<ReminiscenceTopic> fallbackTopics() {
    final copy = [..._fallbackTopics]..shuffle(Random());
    return copy.take(4).toList(growable: false);
  }

  Future<String> extractElderName(String transcript) async {
    final result = await _client.complete(
      messages: [
        const LlmMessage('system', '從自我介紹中擷取稱呼，只回傳名字；無法判斷就回傳「長輩」。'),
        LlmMessage('user', transcript),
      ],
      temperature: 0.1,
      maxTokens: 30,
    );
    return result.replaceAll(RegExp(r'[\n"「」]'), '').trim();
  }

  Future<String> generateExtendedQuestion(
    String previousQuestion,
    String elderResponse,
  ) async {
    return _client.complete(
      messages: [
        const LlmMessage(
          'system',
          '你是親切的台灣回憶治療引導員。根據回答提出一個具體、溫暖、25到45字的繁體中文延伸問題，只回傳問題。',
        ),
        LlmMessage('user', '先前問題：$previousQuestion\n長輩回答：$elderResponse'),
      ],
      temperature: 0.75,
      maxTokens: 100,
    );
  }

  Future<Map<String, dynamic>> extractSceneData(String transcript) async {
    final raw = await _client.complete(
      messages: [
        const LlmMessage(
          'system',
          '把回憶整理成 JSON，只能包含 scene、era、location、keywords；keywords 是繁體中文陣列。',
        ),
        LlmMessage('user', transcript),
      ],
      temperature: 0.1,
      maxTokens: 400,
    );
    return decodeJsonObjectFromText(raw, requiredKey: 'scene');
  }

  Future<List<String>> extractKeywords(String transcript) async {
    final data = await extractSceneData(transcript);
    return (data['keywords'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  static bool _isComplete(ReminiscenceTopic topic) =>
      topic.title.isNotEmpty &&
      topic.question.isNotEmpty &&
      topic.followUpQuestion.isNotEmpty &&
      topic.imagePrompt.isNotEmpty &&
      topic.imageSearchQuery.isNotEmpty &&
      const {
        'childhood_games',
        'school_life',
        'traditional_food',
        'market',
        'farming',
        'railway',
        'festivals',
        'family',
        'work',
        'neighborhood',
        'entertainment',
      }.contains(topic.categoryId);
}
