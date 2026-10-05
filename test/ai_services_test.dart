import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:remini_care_ai_app/models/reminiscence_topic.dart';
import 'package:remini_care_ai_app/services/ai/ai_models.dart';
import 'package:remini_care_ai_app/services/ai/ai_service_exception.dart';
import 'package:remini_care_ai_app/services/ai/llm_client.dart';
import 'package:remini_care_ai_app/services/ai/provider_registry.dart';
import 'package:remini_care_ai_app/services/ai/provider_response_parser.dart';
import 'package:remini_care_ai_app/services/ai/reminiscence_ai_service.dart';
import 'package:remini_care_ai_app/services/image_gen_api_service.dart';
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
                  'content': '{"topics":[]}',
                  'reasoning_content': 'Private analysis, not a final answer',
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

  test('reasoning-only responses are never exposed as final text', () {
    for (final key in ['reasoning_content', 'reasoning', 'analysis']) {
      expect(
        extractProviderMessageText({
          'choices': [
            {
              'message': {'content': null, key: 'Extract name: 王小明?'},
            },
          ],
        }),
        isNull,
      );
    }
  });

  test(
    'name extraction accepts structured name and explicit honorific',
    () async {
      final service = ReminiscenceAiService(
        _FakeLlmClient('{"surname":"王","title":"先生"}'),
      );
      expect(await service.extractElderName('我叫王小明，叫我王先生。'), '王先生');
      final neutral = ReminiscenceAiService(
        _FakeLlmClient('{"surname":"丁","title":null}'),
      );
      expect(await neutral.extractElderName('我叫丁紅圓'), '丁長輩');
    },
  );

  test(
    'name extraction rejects analysis, unknown names and guessed titles',
    () async {
      for (final response in [
        'Extract name: 丁紅圓? Ambiguous;',
        '{"surname":null,"title":null}',
        '{"surname":"陳","title":null}',
        '{"surname":"丁","title":"小姐"}',
        '{"surname":"丁","title":"Extract name"}',
        '{"surname":"丁","title":',
        '{"surname":"丁紅圓","title":null}',
        '{"surname":"丁紅","title":null}',
      ]) {
        expect(
          () => ReminiscenceAiService(
            _FakeLlmClient(response),
          ).extractElderName('我叫丁紅圓'),
          throwsA(isA<AiServiceException>()),
        );
      }
    },
  );

  test(
    'surname display ignores given-name homophones and preserves compounds',
    () async {
      final service = ReminiscenceAiService(
        _FakeLlmClient('{"surname":"王","title":"先生"}'),
      );
      for (final givenName in ['鴻', '泓']) {
        expect(await service.extractElderName('我叫王$givenName，叫我王先生'), '王先生');
      }
      final compound = ReminiscenceAiService(
        _FakeLlmClient('{"surname":"歐陽","title":"女士"}'),
      );
      expect(await compound.extractElderName('我叫歐陽秀，請叫我歐陽女士'), '歐陽女士');
    },
  );

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
      ProviderRegistry.imagePresets['cloudflare']!.supports(
        ProviderCapability.imageEditing,
      ),
      isTrue,
    );
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

  test('Cloudflare client requests a 1.6:1 image from the Worker', () async {
    late http.Request captured;
    final store = _MemoryImageStore();
    final client = CloudflareWorkerImageClient(
      config: ProviderRegistry.imagePresets['cloudflare']!.copyWithForTest(
        baseUrl: 'https://image-worker.test/',
      ),
      appToken: 'app-secret',
      store: store,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'b64_json': base64Encode([1, 2, 3]),
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(await client.generate(prompt: '1960s Taiwan'), 'memory://generated');
    expect(
      captured.url.toString(),
      'https://image-worker.test/v1/images/generations',
    );
    expect(captured.headers['Authorization'], 'Bearer app-secret');
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['width'], 1024);
    expect(payload['height'], 640);
    expect(store.bytes, [1, 2, 3]);
  });

  test(
    'Cloudflare edit sends a compressed reference and preservation prompt',
    () async {
      late Map<String, dynamic> payload;
      final client = CloudflareWorkerImageClient(
        config: ProviderRegistry.imagePresets['cloudflare']!.copyWithForTest(
          baseUrl: 'https://image-worker.test',
        ),
        appToken: 'app-secret',
        store: _MemoryImageStore(),
        preprocessor: _FakePreprocessor(),
        httpClient: MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'b64_json': base64Encode([4, 5, 6]),
                },
              ],
            }),
            200,
          );
        }),
      );

      await client.edit(
        imagePath: 'ignored.png',
        instruction: 'remove the car',
      );
      expect(payload['imageBase64'], base64Encode([7, 8, 9]));
      expect(payload['imageMimeType'], 'image/jpeg');
      expect(payload['prompt'], contains('Preserve the same people'));
      expect(payload['prompt'], contains('remove the car'));
    },
  );

  test('Cloudflare edit input is resized below the model limit', () async {
    final directory = await Directory.systemTemp.createTemp('reminicare_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}large.png');
    await file.writeAsBytes(img.encodePng(img.Image(width: 800, height: 600)));
    final prepared = await const ImageInputPreprocessor().prepare(file.path);
    final decoded = img.decodeJpg(prepared.bytes)!;
    expect(decoded.width, 504);
    expect(decoded.height, 378);
    expect(prepared.mimeType, 'image/jpeg');
  });

  for (final status in [401, 429, 502]) {
    test(
      'Cloudflare HTTP $status produces a typed error without retry',
      () async {
        var calls = 0;
        final client = CloudflareWorkerImageClient(
          config: ProviderRegistry.imagePresets['cloudflare']!.copyWithForTest(
            baseUrl: 'https://image-worker.test',
          ),
          appToken: 'app-secret',
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('{}', status);
          }),
        );
        await expectLater(
          client.generate(prompt: 'Taiwan'),
          throwsA(
            isA<AiServiceException>().having(
              (error) => error.kind,
              'kind',
              status == 401
                  ? AiServiceErrorKind.authentication
                  : status == 429
                  ? AiServiceErrorKind.rateLimit
                  : AiServiceErrorKind.network,
            ),
          ),
        );
        expect(calls, 1);
      },
    );
  }

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

extension on ImageProviderConfig {
  ImageProviderConfig copyWithForTest({required String baseUrl}) =>
      ImageProviderConfig(
        id: id,
        displayName: displayName,
        baseUrl: baseUrl,
        generationModel: generationModel,
        apiKeyReference: apiKeyReference,
        capabilities: capabilities,
        editModel: editModel,
        timeout: timeout,
      );
}

class _MemoryImageStore extends LocalImageStore {
  List<int>? bytes;

  @override
  Future<String> save(Uint8List value, {required String prefix}) async {
    bytes = value;
    return 'memory://$prefix';
  }
}

class _FakePreprocessor extends ImageInputPreprocessor {
  @override
  Future<PreparedImage> prepare(String path) async =>
      PreparedImage(Uint8List.fromList([7, 8, 9]), 'image/jpeg');
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
