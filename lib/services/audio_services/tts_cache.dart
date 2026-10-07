import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'speech_services.dart';

class TtsCache {
  TtsCache({
    required this.service,
    required this.identity,
    required this.directory,
  });
  final ITTSService service;
  final String identity;
  final Future<Directory> Function() directory;
  final Map<String, Future<String?>> _pending = {};
  static Future<void> _writes = Future.value();
  static const indexKey = 'tts_audio_cache_index_v1';
  static const maximumBytes = 100 * 1024 * 1024;

  Future<String?> resolve(String text, String language) {
    final key = jsonEncode([identity, language, text]);
    return _pending.putIfAbsent(
      key,
      () => _resolve(key, text, language).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<String?> _resolve(String key, String text, String language) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> readIndex() {
      try {
        return Map<String, dynamic>.from(
          jsonDecode(prefs.getString(indexKey) ?? '{}'),
        );
      } catch (_) {
        return {};
      }
    }

    final existing = readIndex()[key];
    if (existing is Map &&
        existing['path'] is String &&
        await File(existing['path']).exists()) {
      final touch = _writes.then((_) async {
        final index = readIndex();
        if (index[key] is Map) {
          index[key]['lastUsed'] = DateTime.now().millisecondsSinceEpoch;
          await prefs.setString(indexKey, jsonEncode(index));
        }
      });
      _writes = touch.catchError((Object _) {});
      await touch;
      return existing['path'] as String;
    }
    final audio = await service
        .generateSpeech(text, language)
        .timeout(const Duration(seconds: 65));
    if (audio == null || audio.isEmpty || audio.length > maximumBytes) {
      return null;
    }
    final root = await directory();
    await root.create(recursive: true);
    final file = File(
      '${root.path}/tts_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(audio, flush: true);
    final write = _writes.then((_) async {
      final index = readIndex();
      index[key] = {
        'path': file.path,
        'size': audio.length,
        'lastUsed': DateTime.now().millisecondsSinceEpoch,
        'language': language,
        'text': text,
        'provider': identity,
      };
      var size = index.values.whereType<Map>().fold<int>(
        0,
        (sum, row) => sum + ((row['size'] as int?) ?? 0),
      );
      final oldest = index.keys.where((k) => k != key).toList()
        ..sort(
          (a, b) => ((index[a]['lastUsed'] as int?) ?? 0).compareTo(
            (index[b]['lastUsed'] as int?) ?? 0,
          ),
        );
      for (final oldKey in oldest) {
        if (size <= maximumBytes) break;
        final row = index.remove(oldKey);
        size -= (row['size'] as int?) ?? 0;
        final oldPath = row['path'];
        // Only cache-owned files in the configured directory may be removed.
        if (oldPath is String &&
            File(oldPath).parent.path == root.path &&
            File(oldPath).uri.pathSegments.last.startsWith('tts_')) {
          try {
            await File(oldPath).delete();
          } catch (_) {}
        }
      }
      await prefs.setString(indexKey, jsonEncode(index));
    });
    _writes = write.catchError((Object _) {});
    await write;
    return file.path;
  }
}
