import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remini_care_ai_app/models/reminiscence_topic.dart';
import 'package:remini_care_ai_app/services/ai/cloud_vision_reranker.dart';
import 'package:remini_care_ai_app/services/topic_image_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const topic = ReminiscenceTopic(
    title: '放氣球',
    question: '以前看過氣球嗎？',
    followUpQuestion: '那天和誰一起？',
    imagePrompt: 'balloons in vintage Taiwan',
    imageSearchQuery: '台灣 氣球 老照片 | vintage Taiwan balloons',
  );

  test('searches both languages, filters licenses and reuses cache', () async {
    final png = await _pngBytes();
    var searchRequests = 0;
    var imageRequests = 0;
    final cache = _MemoryTopicImageCache();
    final client = TopicImageSearchClient(
      cache: cache,
      httpClient: MockClient((request) async {
        if (request.url.host == 'api.openverse.org') {
          searchRequests++;
          expect(request.url.queryParameters['mature'], 'false');
          expect(request.url.queryParameters['category'], isNull);
          expect(request.url.queryParameters['source'], isNull);
          return http.Response(
            jsonEncode({
              'results': [
                _candidate('adult', mature: true),
                _candidate('noncommercial', license: 'by-nc'),
                _candidate('balloon'),
              ],
            }),
            200,
          );
        }
        imageRequests++;
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );

    final first = await client.findForTopic(topic);
    final second = await client.findForTopic(topic);

    expect(first.sourceId, 'wikimedia:balloon');
    expect(first.attribution.license, 'BY');
    expect(second.sourceId, first.sourceId);
    expect(searchRequests, 2, reason: '中英文各搜尋一次');
    expect(imageRequests, 1, reason: '第二次應直接使用快取');
  });

  test('tries the next candidate when a download is not an image', () async {
    final png = await _pngBytes();
    final client = TopicImageSearchClient(
      cache: _MemoryTopicImageCache(),
      httpClient: MockClient((request) async {
        if (request.url.host == 'api.openverse.org') {
          return http.Response(
            jsonEncode({
              'results': [
                _candidate('first', title: 'Taiwan balloons'),
                _candidate('second', title: 'Taiwan balloon festival'),
              ],
            }),
            200,
          );
        }
        if (request.url.path.contains('first')) {
          return http.Response(
            'not an image',
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );

    final result = await client.findForTopic(topic);
    expect(result.sourceId, 'wikimedia:second');
  });

  test('does not return an excluded source image', () async {
    final client = TopicImageSearchClient(
      cache: _MemoryTopicImageCache(),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'results': [_candidate('balloon')],
          }),
          200,
        ),
      ),
    );

    expect(
      () => client.findForTopic(
        topic,
        excludedSourceIds: const {'wikimedia:balloon'},
      ),
      throwsA(isA<TopicImageSearchException>()),
    );
  });

  test('accepts only Wikimedia or Flickr photographic results', () async {
    final client = TopicImageSearchClient(
      cache: _MemoryTopicImageCache(),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'results': [
              _candidate('other-source', source: 'stocksnap'),
              _candidate('illustration', category: 'illustration'),
            ],
          }),
          200,
        ),
      ),
    );

    expect(
      () => client.findForTopic(topic),
      throwsA(isA<TopicImageSearchException>()),
    );
  });

  test('cloud reranker controls which candidate is downloaded', () async {
    final png = await _pngBytes();
    final client = TopicImageSearchClient(
      cache: _MemoryTopicImageCache(),
      reranker: _ChooseSecondReranker(),
      httpClient: MockClient((request) async {
        if (request.url.host == 'api.openverse.org') {
          return http.Response(
            jsonEncode({
              'results': [_candidate('first'), _candidate('second')],
            }),
            200,
          );
        }
        expect(request.url.path, contains('second'));
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );

    final result = await client.findForTopic(topic);
    expect(result.sourceId, 'wikimedia:second');
  });

  test(
    'Wikimedia client uses one exact category request and one download',
    () async {
      final png = await _pngBytes();
      var apiRequests = 0;
      var imageRequests = 0;
      final client = WikimediaTopicImageSearchClient(
        cache: _MemoryTopicImageCache(),
        httpClient: MockClient((request) async {
          if (request.url.host == 'commons.wikimedia.org') {
            apiRequests++;
            expect(
              request.url.queryParameters['gcmtitle'],
              'Category:Historical images of schools in Taiwan',
            );
            expect(request.url.queryParameters['gcmlimit'], '20');
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': [
                    _commonsCandidate(1, license: 'CC BY-NC 4.0'),
                    _commonsCandidate(2, license: 'Public domain'),
                  ],
                },
              }),
              200,
            );
          }
          imageRequests++;
          expect(request.url.path, contains('school-2'));
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      const schoolTopic = ReminiscenceTopic(
        title: '上學',
        question: '以前怎麼上學？',
        followUpQuestion: '記得哪位老師？',
        imagePrompt: 'historical Taiwan school',
        imageSearchQuery: '台灣 小學 老照片 | historical Taiwan school',
        categoryId: 'school_life',
      );

      final first = await client.findForTopic(schoolTopic);
      final second = await client.findForTopic(schoolTopic);

      expect(first.sourceId, 'wikimedia:2');
      expect(first.attribution.source, 'Wikimedia Commons');
      expect(first.attribution.license, 'Public domain');
      expect(second.sourceId, first.sourceId);
      expect(apiRequests, 1);
      expect(imageRequests, 1);
    },
  );

  test('Wikimedia client rejects a topic without a controlled category', () {
    final client = WikimediaTopicImageSearchClient(
      cache: _MemoryTopicImageCache(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      () => client.findForTopic(topic),
      throwsA(isA<TopicImageSearchException>()),
    );
  });

  test(
    'railway uses the tested Commons search instead of an empty category',
    () async {
      final client = WikimediaTopicImageSearchClient(
        cache: _MemoryTopicImageCache(),
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['generator'], 'search');
          expect(
            request.url.queryParameters['gsrsearch'],
            'Taiwan railway station historical',
          );
          expect(request.url.queryParameters['gcmtitle'], isNull);
          return http.Response(
            jsonEncode({
              'query': {'pages': []},
            }),
            200,
          );
        }),
      );
      const railway = ReminiscenceTopic(
        title: '搭火車',
        question: '以前搭火車去哪裡？',
        followUpQuestion: '和誰一起去？',
        imagePrompt: 'historical Taiwan railway station',
        imageSearchQuery: '台灣 老火車站 | historical Taiwan railway station',
        categoryId: 'railway',
      );

      expect(
        () => client.findForTopic(railway),
        throwsA(isA<TopicImageSearchException>()),
      );
    },
  );

  test('historical photo ranking rejects maps and illustrations', () async {
    final png = await _pngBytes();
    final client = WikimediaTopicImageSearchClient(
      cache: _MemoryTopicImageCache(),
      httpClient: MockClient((request) async {
        if (request.url.host == 'commons.wikimedia.org') {
          final map = _commonsCandidate(10, license: 'Public domain');
          map['title'] = 'File:Botanical map of north Formosa 1896.jpg';
          final harvest = _commonsCandidate(11, license: 'Public domain');
          harvest['title'] =
              'File:Harvesting on the paddy fields in Taichu.jpg';
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [map, harvest],
              },
            }),
            200,
          );
        }
        expect(request.url.path, contains('school-11'));
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    const farming = ReminiscenceTopic(
      title: '農忙',
      question: '以前如何收割？',
      followUpQuestion: '大家怎麼分工？',
      imagePrompt: 'rice harvest',
      imageSearchQuery: '台灣 稻田 收割 | Taiwan rice harvesting',
      categoryId: 'farming',
    );

    final result = await client.findForTopic(farming);
    expect(result.sourceId, 'wikimedia:11');
  });
}

Map<String, dynamic> _commonsCandidate(int id, {required String license}) => {
  'pageid': id,
  'title': 'File:Taiwan school-$id.png',
  'canonicalurl': 'https://commons.wikimedia.org/wiki/File:school-$id',
  'imageinfo': [
    {
      'mime': 'image/png',
      'thumburl': 'https://upload.wikimedia.test/school-$id.png',
      'extmetadata': {
        'LicenseShortName': {'value': license},
        'LicenseUrl': {
          'value': 'https://creativecommons.org/publicdomain/mark/1.0/',
        },
        'Artist': {'value': '<b>Test photographer</b>'},
        'ImageDescription': {'value': 'Historical school in Taiwan'},
      },
    },
  ],
};

Map<String, dynamic> _candidate(
  String id, {
  String license = 'by',
  bool mature = false,
  String title = 'Vintage Taiwan balloon photograph',
  String source = 'wikimedia',
  String? category,
}) => {
  'id': id,
  'title': title,
  'creator': 'Test Photographer',
  'source': source,
  'category': ?category,
  'license': license,
  'license_url': 'https://creativecommons.org/licenses/by/4.0/',
  'foreign_landing_url': 'https://commons.wikimedia.org/wiki/File:$id',
  'thumbnail': 'https://images.test/$id.png',
  'width': 800,
  'height': 600,
  'mature': mature,
  'tags': [
    {'name': 'Taiwan'},
    {'name': 'balloon'},
  ],
};

Future<Uint8List> _pngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 640, 480),
    Paint()..color = Colors.amber,
  );
  final image = await recorder.endRecording().toImage(640, 480);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _MemoryTopicImageCache implements ITopicImageCache {
  TopicThumbnailResult? value;

  @override
  Future<TopicThumbnailResult?> find(
    String query, {
    Set<String> excludedSourceIds = const {},
  }) async => value != null && !excludedSourceIds.contains(value!.sourceId)
      ? value
      : null;

  @override
  Future<TopicThumbnailResult> store({
    required String query,
    required Uint8List bytes,
    required String extension,
    required String sourceId,
    required int width,
    required int height,
    required TopicImageAttribution attribution,
  }) async {
    return value = TopicThumbnailResult(
      path: '/cache/$sourceId.$extension',
      sourceId: sourceId,
      width: width,
      height: height,
      attribution: attribution,
    );
  }
}

class _ChooseSecondReranker implements ITopicImageReranker {
  @override
  Future<List<String>> rank({
    required ReminiscenceTopic topic,
    required List<TopicVisionCandidate> candidates,
  }) async => [
    candidates
        .singleWhere((candidate) => candidate.sourceId.endsWith('second'))
        .sourceId,
  ];
}
