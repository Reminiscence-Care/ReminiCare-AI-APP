import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remini_care_ai_app/services/app_log.dart';
import 'package:remini_care_ai_app/screens/app_log_screen.dart';

void main() {
  test(
    'STT text appears identically in console and exported app log',
    () async {
      final lines = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
      addTearDown(() => debugPrint = originalPrint);
      final log = AppLog();
      log.recordTranscription('測試辨識\n第二句', operationId: 7);
      log.recordTranscription('測試部分文字', operationId: 8, partial: true);
      expect(lines, log.entries.map((entry) => entry.line).toList());
      expect(log.exportText(), contains('辨識結果'));
      expect(log.exportText(), contains('部分辨識結果（未完整成功）'));
      expect(log.entries.first.transcript, '測試辨識\n第二句');
      expect(log.entries.first.line.split('\n'), hasLength(1));
      log.clear();
      expect(log.exportText(), isEmpty);
      log.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('STT text is bounded without splitting Unicode characters', () async {
    final log = AppLog(capacity: 1, mirrorToConsole: false);
    log.recordTranscription(
      '😀' * (AppLog.maxTranscriptRunes + 1),
      operationId: 1,
    );
    expect(
      log.entries.single.transcript!.runes.length,
      AppLog.maxTranscriptRunes,
    );
    expect(log.entries.single.transcriptTruncated, isTrue);
    expect(log.exportText(), contains('文字已截短'));
    log.recordTranscription('', operationId: 2);
    expect(log.entries.single.operationId, 2);
    expect(log.entries.single.transcript, isEmpty);
    log.dispose();
    log.recordTranscription('disposed result', operationId: 3);
    expect(log.entries.single.operationId, 2);
    await Future<void>.delayed(Duration.zero);
  });
  test(
    'bounded entries preserve time and only known diagnostic details',
    () async {
      final log = AppLog(capacity: 2, mirrorToConsole: false);
      log.record(
        LogArea.stt,
        LogEvent.started,
        detail: 'secret-token-and-personal-transcript',
      );
      expect(log.exportText(), isNot(contains('secret-token')));
      expect(log.entries.single.detail, 'unexpected');
      log.record(
        LogArea.stt,
        LogEvent.progress,
        operationId: 3,
        complete: 1,
        total: 2,
      );
      log.record(LogArea.stt, LogEvent.completed, durationMs: 42, bytes: 512);
      expect(log.entries, hasLength(2));
      expect(log.entries.first.id, 2);
      expect(log.exportText(), contains('進度=1/2'));
      expect(log.exportText(), contains('耗時=42 ms'));
      expect(log.entries.last.time, isA<DateTime>());
      expect(log.entries.last.elapsed, greaterThanOrEqualTo(Duration.zero));
      log.clear();
      expect(log.entries, isEmpty);
      // A queued notification must not call a disposed notifier.
      log.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  testWidgets(
    'global entry survives every route and a modal, with live updates and safe return',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      final log = AppLog(mirrorToConsole: false);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          builder: (_, child) =>
              AppLogOverlay(navigatorKey: key, log: log, child: child!),
          home: const Scaffold(appBar: null, body: Text('home')),
        ),
      );
      final button = find.byKey(const ValueKey('app-log-button'));
      for (final page in ['home', 'flow', 'history', 'detail', 'cache']) {
        if (page != 'home') {
          key.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(page))),
          );
          await tester.pumpAndSettle();
        }
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('執行紀錄'), findsOneWidget);
        log.record(LogArea.flow, LogEvent.stageChanged, detail: 'introduction');
        log.recordTranscription('畫面測試辨識文字', operationId: 4);
        await tester.pumpAndSettle();
        expect(find.textContaining('自我介紹'), findsWidgets);
        expect(find.textContaining('畫面測試辨識文字'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('clear-app-log')));
        await tester.pumpAndSettle();
        expect(find.text('尚無執行紀錄'), findsOneWidget);
        key.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text(page), findsOneWidget);
      }
      final dialog = showDialog<void>(
        context: key.currentContext!,
        builder: (_) => const AlertDialog(title: Text('modal')),
      );
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('執行紀錄'), findsOneWidget);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('modal'), findsOneWidget);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      await dialog;
      await tester.pumpWidget(const SizedBox.shrink());
      log.dispose();
    },
  );
}
