import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remini_care_ai_app/models/reminiscence_topic.dart';
import 'package:remini_care_ai_app/services/ai/ai_models.dart';
import 'package:remini_care_ai_app/services/ai/cloud_vision_reranker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cloud vision sends one low-resolution contact sheet and maps indexes',
    () async {
      final png = await _pngBytes();
      var cloudCalls = 0;
      final client = CloudTopicImageReranker(
        config: const VisionProviderConfig(
          id: 'test',
          displayName: 'Test Vision',
          baseUrl: 'https://vision.test/v1',
          model: 'vision-test',
          apiKeyReference: 'TEST_KEY',
        ),
        apiKey: 'secret',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(
              png,
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          cloudCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'vision-test');
          final content = body['messages'][0]['content'] as List<dynamic>;
          final imageParts = content
              .where((part) => part['type'] == 'image_url')
              .toList();
          expect(imageParts, hasLength(1));
          expect(
            imageParts.single['image_url']['url'],
            startsWith('data:image/png;base64,'),
          );
          expect(request.body, isNot(contains('長輩姓名')));
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '1. {"rankedIndexes":[1]}\n2\\. {"rankedIndexes":[2,1,2,99]}',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.rank(
        topic: const ReminiscenceTopic(
          title: '童年遊戲',
          question: '以前玩什麼？',
          followUpQuestion: '和誰一起玩？',
          imagePrompt: 'Taiwanese children playing traditional games',
          imageSearchQuery: '台灣 童年遊戲 | Taiwan childhood games',
        ),
        candidates: const [
          TopicVisionCandidate(
            sourceId: 'wikimedia:first',
            imageUrl: 'https://images.test/first.png',
            title: 'First',
          ),
          TopicVisionCandidate(
            sourceId: 'flickr:second',
            imageUrl: 'https://images.test/second.png',
            title: 'Second',
          ),
        ],
      );

      expect(result, ['flickr:second', 'wikimedia:first']);
      expect(cloudCalls, 1);
    },
  );
}

Future<Uint8List> _pngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 640, 480),
    Paint()..color = Colors.teal,
  );
  final image = await recorder.endRecording().toImage(640, 480);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
