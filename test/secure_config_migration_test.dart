import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  test('legacy plaintext secrets migrate once and are removed', () async {
    SharedPreferences.setMockInitialValues({
      'NVIDIA_API_KEY': 'legacy-secret',
      'VOICE_MAX_RECORD_LIMIT': '240',
    });
    final secureValues = <String, String>{};
    var writes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key']?.toString();
          switch (call.method) {
            case 'read':
              return key == null ? null : secureValues[key];
            case 'write':
              writes++;
              if (key != null) secureValues[key] = args['value'].toString();
              return null;
            case 'delete':
              if (key != null) secureValues.remove(key);
              return null;
          }
          return null;
        });

    await ReminiCareConfig.loadConfig();
    final prefs = await SharedPreferences.getInstance();
    expect(ReminiCareConfig.nvidiaApiKey, 'legacy-secret');
    expect(secureValues['NVIDIA_API_KEY'], 'legacy-secret');
    expect(prefs.containsKey('NVIDIA_API_KEY'), isFalse);
    expect(prefs.getBool('secure_storage_migration_v1'), isTrue);
    expect(ReminiCareConfig.maxRecordLimit, '240');

    await ReminiCareConfig.loadConfig();
    expect(writes, 1);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'failed secure storage write leaves config revision and snapshot intact',
    () async {
      SharedPreferences.setMockInitialValues({
        'secure_storage_migration_v1': true,
        'NVIDIA_LLM_MODEL': 'old-model',
      });
      final secureValues = <String, String>{'NVIDIA_API_KEY': 'old-key'};
      var fail = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final key = args['key'];
            if (call.method == 'read') return secureValues[key];
            if (call.method == 'write') {
              if (fail && args['value'] == 'new-key') {
                throw PlatformException(code: 'test-failure');
              }
              secureValues[key] = args['value'];
            }
            return null;
          });
      await ReminiCareConfig.loadConfig();
      final revision = ReminiCareConfig.revision;
      fail = true;
      await expectLater(
        ReminiCareConfig.saveConfig({
          'NVIDIA_LLM_MODEL': 'new-model',
          'NVIDIA_API_KEY': 'new-key',
        }),
        throwsException,
      );
      expect(ReminiCareConfig.revision, revision);
      expect(ReminiCareConfig.getValue('NVIDIA_LLM_MODEL'), 'old-model');
      expect(
        (await SharedPreferences.getInstance()).getString('NVIDIA_LLM_MODEL'),
        'old-model',
      );
      expect(secureValues['NVIDIA_API_KEY'], 'old-key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
