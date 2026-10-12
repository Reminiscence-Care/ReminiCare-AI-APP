import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:remini_care_ai_app/theme/remini_care_theme.dart';

void main() {
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'secure_storage_migration_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
  });

  for (final scenario in const [
    (Size(1180, 820), 1.0),
    (Size(1024, 768), 1.0),
    (Size(820, 1180), 1.0),
    (Size(390, 844), 1.0),
    (Size(1180, 820), 1.5),
    (Size(390, 844), 2.0),
  ]) {
    testWidgets('home start is visible without scrolling at $scenario', (
      tester,
    ) async {
      final (size, scale) = scenario;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ReminiCareTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, bottom: 20),
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: const HomeScreen(),
          ),
        );
        await ReminiCareConfig.loadConfig();
      });
      await tester.pumpAndSettle();
      final start = find.byKey(const ValueKey('home-start'));
      final rect = tester.getRect(start);
      expect(rect.top, greaterThanOrEqualTo(80));
      expect(rect.bottom, lessThanOrEqualTo(size.height - 20));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.height, greaterThanOrEqualTo(76));
      expect(start.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      if (scale == 1) {
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable),
        );
        expect(scrollable.position.maxScrollExtent, 0);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
