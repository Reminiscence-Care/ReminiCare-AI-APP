import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remini_care_ai_app/models/reminiscence_topic.dart';
import 'package:remini_care_ai_app/services/ai/ai_models.dart';
import 'package:remini_care_ai_app/services/ai/ai_service_exception.dart';
import 'package:remini_care_ai_app/services/ai/llm_client.dart';
import 'package:remini_care_ai_app/services/ai/provider_registry.dart';
import 'package:remini_care_ai_app/services/ai/provider_response_parser.dart';
import 'package:remini_care_ai_app/services/ai/reminiscence_ai_service.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

void main() {
  const config = LlmProviderConfig(
    id: 'test',
    displayName: 'Test',
    baseUrl: 'https://example.test/v1/',
    model: 'test-model',
    apiKeyReference: 'TEST_KEY',
  );

  test('OpenAI-compatible client builds a standard request', () async {
    late http.Request captured;
    final client = OpenAiCompatibleLlmClient(
      config: config,
      apiKey: 'secret',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '完成'},
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await client.complete(
      messages: const [LlmMessage('user', '你好')],
    );
    expect(result, '完成');
    expect(captured.url.toString(), 'https://example.test/v1/chat/completions');
    expect(captured.headers['Authorization'], 'Bearer secret');
    expect(jsonDecode(captured.body)['model'], 'test-model');
  });

  test('rate limits are exposed as typed errors', () async {
    final client = OpenAiCompatibleLlmClient(
      config: config,
      apiKey: 'secret',
      httpClient: MockClient((_) async => http.Response('{}', 429)),
    );
    expect(
      () => client.complete(messages: const [LlmMessage('user', '你好')]),
      throwsA(
        isA<AiServiceException>().having(
          (e) => e.kind,
          'kind',
          AiServiceErrorKind.rateLimit,
        ),
      ),
    );
  });

  test('billing failures are exposed as typed errors', () async {
    final client = OpenAiCompatibleLlmClient(
      config: config,
      apiKey: 'secret',
      httpClient: MockClient(
        (_) async =>
            http.Response(jsonEncode({'message': 'insufficient balance'}), 402),
      ),
    );
    expect(
      () => client.complete(messages: const [LlmMessage('user', '你好')]),
      throwsA(
        isA<AiServiceException>().having(
          (e) => e.kind,
          'kind',
          AiServiceErrorKind.billing,
        ),
      ),
    );
  });

  test('JSON mode adds the OpenAI-compatible response format', () async {
    late http.Request captured;
    final client = OpenAiCompatibleLlmClient(
      config: config,
      apiKey: 'secret',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"topics":[]}'},
              },
            ],
          }),
          200,
        );
      }),
    );
    await client.complete(
      messages: const [LlmMessage('user', 'JSON')],
      jsonObject: true,
    );
    expect(jsonDecode(captured.body)['response_format'], {
      'type': 'json_object',
    });
  });

  test('NVIDIA reasoning responses and model options are supported', () async {
    late Map<String, dynamic> requestBody;
    final client = OpenAiCompatibleLlmClient(
      config: const LlmProviderConfig(
        id: 'nvidia',
        displayName: 'NVIDIA',
        baseUrl: 'https://integrate.api.nvidia.com/v1',
        model: 'z-ai/glm-5.3-flash',
        apiKeyReference: 'NVIDIA_API_KEY',
      ),
      apiKey: 'secret',
      httpClient: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': null,
                  'reasoning_content': '{"topics":[]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(
      await client.complete(messages: const [LlmMessage('user', 'JSON')]),
      '{"topics":[]}',
    );
    expect(requestBody['reasoning_effort'], 'low');
    expect(requestBody['chat_template_kwargs'], {'clear_thinking': true});
  });

  test('JSON parser selects the last complete object from model drafts', () {
    final result = decodeJsonObjectFromText(
      '1. {"rankedIndexes":[1]}\n2\\. {"rankedIndexes":[2,1,3]}',
      requiredKey: 'rankedIndexes',
    );
    expect(result['rankedIndexes'], [2, 1, 3]);
  });

  test('topic response requires four unique complete topics', () async {
    final service = ReminiscenceAiService(
      _FakeLlmClient(
        jsonEncode({
          'topics': List.generate(
            4,
            (index) => <String, dynamic>{
              'title': '主題$index',
              'question': '問題$index',
              'followUpQuestion': '延伸$index',
              'imagePrompt': 'prompt $index',
              'imageSearchQuery': '主題$index 台灣 | topic $index Taiwan',
              'categoryId': [
                'childhood_games',
                'school_life',
                'traditional_food',
                'market',
              ][index],
            },
          ),
        }),
      ),
    );
    final topics = await service.recommendTopics();
    expect(topics, hasLength(4));
    expect(topics.map((e) => e.title).toSet(), hasLength(4));
  });

  test('invalid topic JSON uses a four-item fallback', () async {
    final result = await ReminiscenceAiService(
      _FakeLlmClient('not json'),
    ).recommendTopicsWithStatus();
    expect(result.topics, hasLength(4));
    expect(result.topics, everyElement(isA<ReminiscenceTopic>()));
    expect(result.usedFallback, isTrue);
    expect(result.warning, contains('格式不正確'));
  });

  test('provider capabilities distinguish edit from generation', () {
    expect(
      ProviderRegistry.imagePresets['siliconflow']!.supports(
        ProviderCapability.imageEditing,
      ),
      isTrue,
    );
    expect(
      ProviderRegistry.imagePresets['openai']!.supports(
        ProviderCapability.imageEditing,
      ),
      isFalse,
    );
  });

  test('custom provider settings require HTTPS and a model', () {
    final base = <String, String>{
      'selectedLlmProvider': 'custom',
      'CUSTOM_LLM_API_KEY': 'secret',
      'CUSTOM_LLM_MODEL': 'model-a',
      'selectedImageProvider': 'openai',
      'OPENAI_API_KEY': 'secret',
      'OPENAI_LLM_MODEL': 'gpt-4o-mini',
      'selectedVisionProvider': 'openai',
      'OPENAI_VISION_MODEL': 'gpt-4o-mini',
      'selectedSpeechProvider': 'yating',
      'YATING_API_KEY': 'secret',
    };
    expect(
      ReminiCareConfig.validateProviderSettings({
        ...base,
        'CUSTOM_LLM_BASE_URL': 'http://unsafe.test/v1',
      }),
      contains('HTTPS'),
    );
    expect(
      ReminiCareConfig.validateProviderSettings({
        ...base,
        'CUSTOM_LLM_BASE_URL': 'https://safe.test/v1',
      }),
      isNull,
    );
  });
}

class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(this.result);
  final String result;
  @override
  Future<String> complete({
    required List<LlmMessage> messages,
    double temperature = 0.6,
    int maxTokens = 500,
    bool jsonObject = false,
  }) async => result;
}
