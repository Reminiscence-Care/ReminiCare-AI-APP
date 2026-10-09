import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import 'audio_services/wav_audio.dart';
import '../models/reminiscence_topic.dart';
import 'topic_catalog.dart';

enum DebugAudioSlot { introduction, answer, extension, revision }

abstract interface class DebugAudioSource {
  /// Returns an owned temporary copy, never the original sample.
  Future<String> take(DebugAudioSlot slot);
}

class DebugAudioException implements Exception {
  const DebugAudioException(this.message);
  final String message;
}

abstract final class DebugFlow {
  static const topicIds = ['street', 'grocery', 'market', 'railway'];
  static List<ReminiscenceTopic> topics(TopicCatalog catalog) => [
    for (final id in topicIds)
      catalog.topics.firstWhere((topic) => topic.topicId == id),
  ];
}

/// Local acceptance files are not assets and must never be committed.
class ManifestDebugAudioSource implements DebugAudioSource {
  ManifestDebugAudioSource(
    this.files, {
    Future<Directory> Function()? temporary,
  }) : _temporary = temporary ?? getTemporaryDirectory;
  final Map<DebugAudioSlot, List<String>> files;
  final Future<Directory> Function() _temporary;
  final _positions = <DebugAudioSlot, int>{};

  static Future<ManifestDebugAudioSource> load(
    String path, {
    Future<Directory> Function()? temporary,
  }) async {
    try {
      final manifest = File(path).absolute;
      final rows = jsonDecode(await manifest.readAsString());
      if (rows is! Map<String, dynamic>) throw const FormatException();
      final files = <DebugAudioSlot, List<String>>{};
      for (final slot in DebugAudioSlot.values) {
        final value =
            rows[slot.name] ?? (slot == DebugAudioSlot.revision ? [] : null);
        if (value is! List ||
            value.any((p) => p is! String || p.trim().isEmpty)) {
          throw const FormatException();
        }
        if (slot != DebugAudioSlot.revision && value.isEmpty) {
          throw const FormatException();
        }
        files[slot] = [
          for (final name in value.cast<String>())
            manifest.parent.uri
                .resolveUri(Uri.file(name, windows: Platform.isWindows))
                .toFilePath(),
        ];
      }
      if (files[DebugAudioSlot.answer]!.length != 1 ||
          files[DebugAudioSlot.extension]!.length != 1) {
        throw const FormatException();
      }
      return ManifestDebugAudioSource(files, temporary: temporary);
    } catch (_) {
      throw const DebugAudioException('測試清單無法讀取或格式不符。');
    }
  }

  @override
  Future<String> take(DebugAudioSlot slot) async {
    final index = _positions[slot] ?? 0;
    final queue = files[slot] ?? const <String>[];
    if (index >= queue.length) {
      throw const DebugAudioException('此階段的測試音檔已耗盡。');
    }
    File? copy;
    try {
      final bytes = await File(queue[index]).readAsBytes();
      final audio = WavAudio.parse(bytes);
      if (audio.pcm.isEmpty) throw const FormatException();
      final root = await _temporary();
      await root.create(recursive: true);
      copy = File(
        '${root.path}/reminicare_chat_smart_debug_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await copy.writeAsBytes(bytes, flush: true);
      _positions[slot] = index + 1;
      return copy.path;
    } catch (_) {
      if (copy != null && await copy.exists()) await copy.delete();
      throw const DebugAudioException('測試音檔無法讀取；需為 16kHz、單聲道、PCM16 WAV。');
    }
  }
}
