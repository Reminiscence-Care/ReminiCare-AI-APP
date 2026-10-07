import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remini_care_ai_app/models/participant_address.dart';
import 'package:remini_care_ai_app/screens/life_screen/controllers/life_screen_controller.dart';
import 'package:remini_care_ai_app/screens/life_screen/widgets/stage_views.dart';
import 'package:remini_care_ai_app/screens/life_screen/widgets/participant_address_dialog.dart';

void main() {
  test('local candidates preserve original spelling and compound surnames', () {
    expect(ParticipantAddress.candidatesFor('於'), ['於', '余', '于', '俞']);
    expect(ParticipantAddress.candidatesFor('王'), ['王']);
    final compound = ParticipantAddress.fromDisplayName('歐陽女士');
    expect(compound.surname, '歐陽');
    expect(compound.title, '女士');
    expect(const ParticipantAddress('第五', '長輩').isValid, isTrue);
    expect(const ParticipantAddress('', '先生').isValid, isFalse);
    expect(const ParticipantAddress('余先生', '先生').isValid, isFalse);
  });

  test(
    'manual correction is pending until participant confirmation; stale edits ignored',
    () {
      final controller = LifeScreenController()
        ..restoreForTesting(stage: LifeStage.introduction)
        ..restoreForTesting(introductionState: IntroductionState.confirmed)
        ..restoreForTesting(currentElderName: '於長輩');
      final revision = controller.introductionRevision;
      controller.correctParticipantAddress(
        const ParticipantAddress('余', '先生'),
        revision: revision,
      );
      expect(controller.currentElderName, '余先生');
      expect(controller.elderNames, isEmpty);
      controller.addNextParticipant();
      expect(controller.elderNames, ['余先生']);
      controller.correctParticipantAddress(
        const ParticipantAddress('於', '長輩'),
        revision: revision,
      );
      expect(controller.currentElderName, isEmpty);
      controller.dispose();
    },
  );

  test(
    'manual correction works after failed introduction and ignores invalid input',
    () {
      final controller = LifeScreenController()
        ..restoreForTesting(stage: LifeStage.introduction)
        ..restoreForTesting(errorMessage: '姓名辨識失敗');
      controller.correctParticipantAddress(
        const ParticipantAddress('', '長輩'),
        revision: 0,
      );
      expect(controller.currentElderName, isEmpty);
      controller.correctParticipantAddress(
        const ParticipantAddress('第五', '女士'),
        revision: 0,
      );
      expect(controller.currentElderName, '第五女士');
      expect(controller.introductionState, IntroductionState.confirmed);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'selecting 余 and confirming updates address; cancellation does not',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = LifeScreenController()
        ..restoreForTesting(stage: LifeStage.introduction)
        ..restoreForTesting(introductionState: IntroductionState.confirmed)
        ..restoreForTesting(currentElderName: '於長輩');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => IntroductionStage(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.text('修改稱呼'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('余'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.currentElderName, '於長輩');
      await tester.tap(find.text('修改稱呼'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('余'));
      await tester.tap(find.text('確認稱呼'));
      await tester.pumpAndSettle();
      expect(find.text('稱呼您：余長輩'), findsOneWidget);
      expect(controller.elderNames, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'phone dialog accepts rare manual surname and rejects empty input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ParticipantAddress? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<ParticipantAddress>(
                    context: context,
                    builder: (_) => const ParticipantAddressDialog(
                      initial: ParticipantAddress('於', '長輩'),
                    ),
                  );
                },
                child: const Text('開啟'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開啟'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('確認稱呼'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.enterText(find.byType(TextFormField), '第五');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('先生').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認稱呼'));
      await tester.pumpAndSettle();
      expect(result?.displayName, '第五先生');
      expect(tester.takeException(), isNull);
    },
  );
}
