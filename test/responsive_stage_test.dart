import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remini_care_ai_app/models/reminiscence_topic.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';
import 'package:remini_care_ai_app/screens/life_screen/widgets/stage_views.dart';
import 'package:remini_care_ai_app/theme/remini_care_theme.dart';

void main() {
  const topics = [
    ReminiscenceTopic(
      title: '下棋',
      question: '問題一',
      followUpQuestion: '延伸一',
      imagePrompt: 'chess',
      imageSearchQuery: '下棋 | chess',
    ),
    ReminiscenceTopic(
      title: '歌仔戲',
      question: '問題二',
      followUpQuestion: '延伸二',
      imagePrompt: 'opera',
      imageSearchQuery: '歌仔戲 | opera',
    ),
    ReminiscenceTopic(
      title: '菜市場',
      question: '問題三',
      followUpQuestion: '延伸三',
      imagePrompt: 'market',
      imageSearchQuery: '菜市場 | market',
    ),
    ReminiscenceTopic(
      title: '節日',
      question: '問題四',
      followUpQuestion: '延伸四',
      imagePrompt: 'festival',
      imageSearchQuery: '節日 | festival',
    ),
  ];

  for (final size in const [
    Size(1366, 1024),
    Size(820, 1180),
    Size(390, 844),
  ]) {
    testWidgets(
      'topic selection has no overflow at ${size.width}x${size.height}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = LifeScreenController()
          ..stage = LifeStage.topicSelection
          ..topics = topics;
        await tester.pumpWidget(
          MaterialApp(
            theme: ReminiCareTheme.light,
            home: Scaffold(
              body: SafeArea(
                child: ReminiCareViewport(
                  child: TopicSelectionStage(controller: controller),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('今天想聊什麼？'), findsOneWidget);
        expect(find.text('我想聊別的'), findsOneWidget);
        expect(tester.takeException(), isNull);
        controller.dispose();
      },
    );
  }

  testWidgets('live window resize never produces a black/error frame', (
    tester,
  ) async {
    final controller = LifeScreenController()
      ..stage = LifeStage.topicSelection
      ..topics = topics;
    await tester.binding.setSurfaceSize(const Size(1366, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ReminiCareTheme.light,
        home: Scaffold(
          body: ReminiCareViewport(
            child: TopicSelectionStage(controller: controller),
          ),
        ),
      ),
    );

    for (final size in const [
      Size(700, 520),
      Size(280, 260),
      Size(1000, 700),
      Size(390, 844),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      expect(find.byType(ColoredBox), findsWidgets);
      expect(tester.takeException(), isNull);
    }
    controller.dispose();
  });

  testWidgets('topic page explains LLM and image fallback failures', (
    tester,
  ) async {
    final controller = LifeScreenController()
      ..stage = LifeStage.topicSelection
      ..topics = topics
      ..topicWarning = '模型不存在'
      ..imageWarning = '部分主題圖片未找到，仍可直接選擇主題。';
    await tester.pumpWidget(
      MaterialApp(
        theme: ReminiCareTheme.light,
        home: Scaffold(
          body: ReminiCareViewport(
            child: TopicSelectionStage(controller: controller),
          ),
        ),
      ),
    );
    expect(find.textContaining('LLM 未成功'), findsOneWidget);
    expect(find.textContaining('部分主題圖片未找到'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('portrait or wide photos use contain and expose attribution', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1366, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final readyTopic = topics.first.copyWith(
      thumbnailPath: File('assets/images/life_home.png').absolute.path,
      thumbnailWidth: 1600,
      thumbnailHeight: 400,
      thumbnailStatus: ThumbnailStatus.ready,
      thumbnailAttribution: const TopicImageAttribution(
        title: '台灣懷舊照片',
        creator: '測試作者',
        source: 'Wikimedia',
        license: 'CC BY-SA',
        originalUrl: 'https://commons.wikimedia.org/example',
        licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
      ),
    );
    final controller = LifeScreenController()
      ..stage = LifeStage.topicSelection
      ..topics = [readyTopic, ...topics.skip(1)];

    await tester.pumpWidget(
      MaterialApp(
        theme: ReminiCareTheme.light,
        home: Scaffold(
          body: ReminiCareViewport(
            child: TopicSelectionStage(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    final imageFits = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.fit);
    expect(imageFits, contains(BoxFit.cover));
    expect(imageFits, contains(BoxFit.contain));

    await tester.tap(find.byTooltip('圖片來源與授權'));
    await tester.pumpAndSettle();
    expect(find.text('作者：測試作者'), findsOneWidget);
    expect(find.text('來源：Wikimedia'), findsOneWidget);
    expect(find.text('授權：CC BY-SA'), findsOneWidget);
    expect(find.text('查看原圖'), findsOneWidget);
    expect(find.text('查看授權'), findsOneWidget);
    controller.dispose();
  });
}
