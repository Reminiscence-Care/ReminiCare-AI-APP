import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/services/memory_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late MemoryRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('reminicare_memory_test_');
    repository = MemoryRepository(directory: () async => root);
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'legacy migration keeps backup, skips corruption, and runs once',
    () async {
      SharedPreferences.setMockInitialValues({
        'chat_memories': [
          jsonEncode({'topic': '回憶', 'content': '內容', 'imagePath': ''}),
          'broken JSON',
        ],
      });
      expect(await repository.load(), hasLength(1));
      expect(
        jsonDecode(
          await File(
            '${root.path}/reminicare_memories/legacy-backup.json',
          ).readAsString(),
        ),
        hasLength(2),
      );
      expect(await repository.load(), hasLength(1));
      expect(
        (await SharedPreferences.getInstance()).containsKey('chat_memories'),
        isFalse,
      );
      await File(
        '${root.path}/reminicare_memories/corrupt.json',
      ).writeAsString('invalid');
      expect(await repository.load(), hasLength(1));
    },
  );
  test(
    'stable ID prevents duplicate saves and images persist as relative paths',
    () async {
      final directory = Directory('${root.path}/reminicare_images');
      await directory.create();
      final image = File('${directory.path}/generated.png');
      await image.writeAsBytes([1, 2, 3]);
      final id = repository.newId();
      final data = {'topic': '回憶', 'imagePath': image.path};
      await Future.wait([repository.save(id, data), repository.save(id, data)]);
      expect(await repository.load(), hasLength(1));
      final stored = jsonDecode(
        await File('${root.path}/reminicare_memories/$id.json').readAsString(),
      );
      expect(stored['imagePath'], 'reminicare_images/generated.png');
      expect(
        (await repository.load()).single['imagePath'],
        '${root.path}/reminicare_images/generated.png',
      );
    },
  );
  test('shared images are retained until last reference is deleted', () async {
    final directory = Directory('${root.path}/reminicare_images');
    await directory.create();
    final image = File('${directory.path}/shared.png');
    await image.writeAsBytes([1, 2, 3]);
    await repository.save('one', {'imagePath': image.path});
    await repository.save('two', {
      'imagePath': '',
      'turns': [
        {'imagePath': image.path},
      ],
    });
    await repository.delete('one');
    expect(await image.exists(), isTrue);
    await repository.delete('two');
    expect(await image.exists(), isFalse);
  });
  test(
    'draft cleanup never deletes saved images or files outside owned directory',
    () async {
      final directory = Directory('${root.path}/reminicare_images');
      await directory.create();
      final saved = File('${directory.path}/saved.png');
      final draft = File('${directory.path}/draft.png');
      final outside = File('${root.path}/outside.png');
      for (final file in [saved, draft, outside]) {
        await file.writeAsBytes([1]);
      }
      await repository.save('saved', {'imagePath': saved.path});
      await repository.discardImages([saved.path, draft.path, outside.path]);
      expect(await saved.exists(), isTrue);
      expect(await draft.exists(), isFalse);
      expect(await outside.exists(), isTrue);
    },
  );
}
