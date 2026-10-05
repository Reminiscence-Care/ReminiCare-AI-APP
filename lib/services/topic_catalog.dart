import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/reminiscence_topic.dart';

class TopicCatalog {
  TopicCatalog(this.topics);
  final List<ReminiscenceTopic> topics;
  static Future<TopicCatalog> load() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/topics/catalog.json'))
            as List;
    return TopicCatalog(
      data.map((raw) {
        final value = raw as Map<String, dynamic>;
        return ReminiscenceTopic(
          topicId: value['topicId'] as String,
          title: value['title'] as String,
          question: value['question'] as String,
          followUpQuestion: value['followUpQuestion'] as String,
          imagePrompt: value['imagePrompt'] as String,
          imageSearchQuery: '',
          illustrative: value['illustrative'] == true,
          thumbnailPath: 'asset:${value['assetPath']}',
          thumbnailStatus: ThumbnailStatus.ready,
          thumbnailSourceId: value['topicId'] as String,
          thumbnailAttribution: TopicImageAttribution.fromJson(
            value['attribution'] as Map<String, dynamic>,
          ),
        );
      }).toList(),
    );
  }

  List<ReminiscenceTopic> pickFour({Set<String?> excluding = const {}}) {
    final preferred =
        topics.where((topic) => !excluding.contains(topic.topicId)).toList()
          ..shuffle(Random());
    final others =
        topics.where((topic) => excluding.contains(topic.topicId)).toList()
          ..shuffle(Random());
    return [...preferred, ...others].take(4).toList();
  }
}
