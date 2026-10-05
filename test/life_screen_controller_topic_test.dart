import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remini_care_ai_app/models/reminiscence_topic.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';
import 'package:remini_care_ai_app/services/ai/ai_models.dart';
import 'package:remini_care_ai_app/services/ai/llm_client.dart';
import 'package:remini_care_ai_app/services/ai/reminiscence_ai_service.dart';
import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
import 'package:remini_care_ai_app/services/topic_image_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'secure_storage_migration_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test(
    'topic startup calls LLM once and never calls image generation',
    () async {
      final llm = _TopicLlm();
      final images = _CountingImageClient();
      final topicImages = _FakeTopicImageSearch();
      final controller = LifeScreenController(
        aiService: ReminiscenceAiService(llm),
        imageService: images,
        topicImageSearchService: topicImages,
        sttService: _FakeStt(),
      );

      await controller.initialize();

      expect(controller.stage, LifeStage.topicSelection);
      expect(controller.topics, hasLength(4));
      expect(
        controller.topics.map((topic) => topic.thumbnailStatus),
        everyElement(ThumbnailStatus.ready),
      );
      expect(llm.calls, 1);
      expect(topicImages.calls, 4);
      expect(images.generateCalls, 0);
      expect(images.editCalls, 0);

      controller.dispose();
    },
  );
}

class _TopicLlm implements LlmClient {
  int calls = 0;

  @override
  Future<String> complete({
    required List<LlmMessage> messages,
    double temperature = 0.6,
    int maxTokens = 500,
    bool jsonObject = false,
  }) async {
    calls++;
    return '''
      {"topics":[
        {"title":"下棋","question":"以前在哪裡下棋？","followUpQuestion":"和誰一起？","imagePrompt":"chess","imageSearchQuery":"台灣 下棋 老照片 | vintage Taiwan chess","categoryId":"childhood_games"},
        {"title":"菜市場","question":"以前買什麼？","followUpQuestion":"記得什麼味道？","imagePrompt":"market","imageSearchQuery":"台灣 菜市場 老照片 | vintage Taiwan market","categoryId":"market"},
        {"title":"搭火車","question":"以前去哪裡？","followUpQuestion":"和誰同行？","imagePrompt":"train","imageSearchQuery":"台灣 火車 老照片 | vintage Taiwan train","categoryId":"railway"},
        {"title":"歌仔戲","question":"喜歡哪齣戲？","followUpQuestion":"在哪裡看？","imagePrompt":"opera","imageSearchQuery":"台灣 歌仔戲 老照片 | vintage Taiwan opera","categoryId":"entertainment"}
      ]}
    ''';
  }
}

class _CountingImageClient implements IImageGenerationClient {
  int generateCalls = 0;
  int editCalls = 0;

  @override
  ImageProviderConfig get config => const ImageProviderConfig(
    id: 'test',
    displayName: 'Test',
    baseUrl: 'https://example.test',
    generationModel: 'test-image',
    apiKeyReference: 'TEST_KEY',
    capabilities: {ProviderCapability.imageGeneration},
  );

  @override
  Future<String> generate({required String prompt}) async {
    generateCalls++;
    return 'generated.png';
  }

  @override
  Future<String> edit({
    required String imagePath,
    required String instruction,
  }) async {
    editCalls++;
    return 'edited.png';
  }
}

class _FakeTopicImageSearch implements ITopicImageSearchClient {
  int calls = 0;

  @override
  Future<TopicThumbnailResult> findForTopic(
    ReminiscenceTopic topic, {
    Set<String> excludedSourceIds = const {},
  }) async {
    calls++;
    final sourceId = 'wikimedia:${topic.title}';
    return TopicThumbnailResult(
      path: '${topic.title}.jpg',
      sourceId: sourceId,
      width: 1024,
      height: 768,
      attribution: TopicImageAttribution(
        title: topic.title,
        creator: 'Test creator',
        source: 'Wikimedia',
        license: 'CC BY',
        originalUrl: 'https://example.test/${topic.title}',
        licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
      ),
    );
  }
}

class _FakeStt implements ISTTService {
  @override
  Future<String?> transcribe(String audioFilePath) async => null;
}
