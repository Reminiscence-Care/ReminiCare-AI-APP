import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One JSON file per memory; invalid records do not hide valid records.
class MemoryRepository {
  MemoryRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directory;
  static final _queues = <String, Future<void>>{};
  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  Future<T> _serialized<T>(Future<T> Function(Directory root) action) async {
    final root = await _directory();
    final work = (_queues[root.path] ?? Future<void>.value()).then(
      (_) => action(root),
    );
    _queues[root.path] = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return work;
  }

  Directory _records(Directory root) =>
      Directory('${root.path}/reminicare_memories');

  Future<void> _atomic(File target, Object data) async {
    if (await target.exists()) return; // stable ID makes saves idempotent
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(target.path);
  }

  Future<Map<String, dynamic>> _portable(
    Directory root,
    Map<String, dynamic> record,
  ) async {
    Future<String> path(dynamic value) async {
      if (value is! String || value.isEmpty) return '';
      if (value.startsWith('http')) return value;
      if (value.startsWith('reminicare_images/')) return value;
      final file = File(value);
      if (!await file.exists()) return '';
      final destination = Directory('${root.path}/reminicare_images');
      await destination.create(recursive: true);
      if (file.parent.absolute.path == destination.absolute.path) {
        return 'reminicare_images/${file.uri.pathSegments.last}';
      }
      final copy = File(
        '${destination.path}/migrated_${newId()}.${value.toLowerCase().endsWith('.jpg') ? 'jpg' : 'png'}',
      );
      await file.copy(copy.path);
      return 'reminicare_images/${copy.uri.pathSegments.last}';
    }

    final copy = Map<String, dynamic>.from(record);
    copy['imagePath'] = await path(copy['imagePath']);
    final turns = copy['turns'];
    if (turns is List) {
      copy['turns'] = [
        for (final row in turns.whereType<Map>())
          {...row, 'imagePath': await path(row['imagePath'])},
      ];
    }
    final versions = copy['imageVersions'];
    if (versions is List) {
      copy['imageVersions'] = [for (final value in versions) await path(value)];
    }
    return copy;
  }

  Future<void> _migrate(Directory root) async {
    final directory = _records(root);
    await directory.create(recursive: true);
    final marker = File('${directory.path}/migration.complete');
    if (await marker.exists()) return;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getStringList('chat_memories') ?? [];
    final backup = File('${directory.path}/legacy-backup.json');
    if (!await backup.exists()) await _atomic(backup, legacy);
    for (var i = 0; i < legacy.length; i++) {
      Map<String, dynamic> record;
      try {
        record = Map<String, dynamic>.from(jsonDecode(legacy[i]));
      } catch (_) {
        continue;
      }
      final target = File('${directory.path}/legacy-$i.json');
      if (!await target.exists()) {
        final data = await _portable(root, record);
        await _atomic(target, {...data, 'id': 'legacy-$i', 'schemaVersion': 2});
      }
    }
    await marker.writeAsString('2', flush: true);
    // The backup retains every legacy string, including malformed rows.
    await prefs.remove('chat_memories');
  }

  Future<List<Map<String, dynamic>>> _read(Directory root) async {
    final records = <Map<String, dynamic>>[];
    await for (final entry in _records(root).list()) {
      if (entry is! File ||
          !entry.path.endsWith('.json') ||
          entry.uri.pathSegments.last == 'legacy-backup.json') {
        continue;
      }
      try {
        final row = Map<String, dynamic>.from(
          jsonDecode(await entry.readAsString()),
        );
        if (row['id'] is String) records.add(row);
      } catch (_) {}
    }
    records.sort(
      (a, b) => (b['createdAt'] ?? b['date'] ?? '').toString().compareTo(
        (a['createdAt'] ?? a['date'] ?? '').toString(),
      ),
    );
    return records;
  }

  Future<List<Map<String, dynamic>>> load() => _serialized((root) async {
    await _migrate(root);
    final rows = await _read(root);
    return [
      for (final row in rows)
        {
          ...row,
          for (final key in ['date', 'topic', 'content', 'elders'])
            key: row[key]?.toString() ?? '',
          'imagePath': _resolve(root, row['imagePath']),
        },
    ];
  });
  String _resolve(Directory root, dynamic value) {
    if (value is! String) return '';
    if (value.startsWith('reminicare_images/') &&
        !value.contains('..') &&
        !value.contains('\\')) {
      return '${root.path}/$value';
    }
    return value.startsWith('http') ? value : '';
  }

  Future<void> save(String id, Map<String, dynamic> data) =>
      _serialized((root) async {
        if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) {
          throw const FormatException('Invalid memory ID');
        }
        await _migrate(root);
        final target = File('${_records(root).path}/$id.json');
        if (await target.exists()) return;
        await _atomic(target, {
          ...await _portable(root, data),
          'id': id,
          'schemaVersion': 2,
        });
      });
  Set<String> _images(Map<String, dynamic> row) => {
    if (row['imagePath'] is String) row['imagePath'] as String,
    if (row['imageVersions'] is List)
      ...(row['imageVersions'] as List).whereType<String>(),
    if (row['turns'] is List)
      ...((row['turns'] as List)
          .whereType<Map>()
          .map((t) => t['imagePath'])
          .whereType<String>()),
  };
  Future<void> _discard(Directory root, Iterable<String> images) async {
    final used = (await _read(root)).expand(_images).toSet();
    for (final value in images.toSet()) {
      if (value.isEmpty || value.startsWith('http')) continue;
      final relative = value.startsWith('reminicare_images/')
          ? value
          : 'reminicare_images/${File(value).uri.pathSegments.last}';
      final resolved = _resolve(root, relative);
      if (resolved.isEmpty || used.contains(relative)) continue;
      // Never delete a file outside this repository's image directory.
      final image = File(resolved);
      if (image.parent.absolute.path !=
          Directory('${root.path}/reminicare_images').absolute.path) {
        continue;
      }
      if (!value.startsWith('reminicare_images/') &&
          File(value).absolute.path != image.absolute.path) {
        continue;
      }
      try {
        await image.delete();
      } on FileSystemException {
        /* Missing files are already clean. */
      }
    }
  }

  Future<void> discardImages(Iterable<String> paths) =>
      _serialized((root) async {
        await _migrate(root);
        await _discard(root, paths);
      });
  Future<void> delete(String id) => _serialized((root) async {
    await _migrate(root);
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) return;
    final records = await _read(root);
    final match = records.where((row) => row['id'] == id);
    if (match.isEmpty) return;
    final images = _images(match.first);
    await File('${_records(root).path}/$id.json').delete();
    await _discard(root, images);
  });
}
