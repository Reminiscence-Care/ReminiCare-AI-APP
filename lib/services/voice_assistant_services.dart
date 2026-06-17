import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

// 💡 引入全域金鑰與 ASR 服務
import 'speech_services.dart';

class WavInfo {
  final List<int> header;
  final List<int> pcm;
  final int dataChunkSizeOffset;

  WavInfo({
    required this.header,
    required this.pcm,
    required this.dataChunkSizeOffset,
  });
}

// =========================================================================
// 🎙️ 💡 獨立語音助手核心控制器 (VoiceAssistantManager)
// =========================================================================
class VoiceAssistantManager {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ISTTService sttService = YatingSpeechService();

  bool _isRollingWakeWord = false;
  bool _isRollingChatRecord = false;
  final List<String> _recordedChunkPaths = [];

  bool _isRecordingOnHardware = false;

  int _wakeWordSessionId = 0;
  int _chatRecordSessionId = 0;

  void Function()? onStartChatFlow;
  void Function()? onRestartChatFlow;
  void Function()? onEndChatFlow;
  // 💡 修正 1：將回傳單一音檔改為回傳「音檔陣列」，支援超過 30 秒的分段 ASR
  void Function(List<String> mergedAudioPaths)? onSpeechCompleted;

  bool checkCompletedCommands = false;

  bool get isListening => _isRollingWakeWord || _isRollingChatRecord;

  /// 💡 核心修復：在停止硬體後，給予 Windows 麥克風 300 毫秒的強制冷卻釋放時間！
  Future<void> stopActiveAudioOperations() async {
    _isRollingWakeWord = false;
    _isRollingChatRecord = false;
    _wakeWordSessionId++;
    _chatRecordSessionId++;

    try {
      if (_isRecordingOnHardware) {
        await _audioRecorder.stop();
        _isRecordingOnHardware = false;
        // 💡 關鍵：給予 Windows 系統驅動釋放麥克風獨佔權的時間，防止秒啟動造成的閃退與無效錄音！
        if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint("[助理] 停止錄音硬體釋放異常: $e");
    }
    _clearTemporaryChunks();
  }

  void _clearTemporaryChunks() {
    for (var path in _recordedChunkPaths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _recordedChunkPaths.clear();
  }

  void dispose() {
    _isRollingWakeWord = false;
    _isRollingChatRecord = false;
    _wakeWordSessionId++;
    _chatRecordSessionId++;
    if (_isRecordingOnHardware) {
      _audioRecorder.stop();
      _isRecordingOnHardware = false;
    }
    _audioRecorder.dispose();
  }

  // ==========================================
  // 🎙️ 輪詢 A：背景一鍵「喚醒詞」檢測循環
  // ==========================================
  Future<void> startBackgroundWakeWordCycle() async {
    if (_isRollingWakeWord) return;
    _isRollingWakeWord = true;
    _wakeWordSessionId++;
    _runSingleWakeWordCycle(_wakeWordSessionId);
  }

  Future<void> _runSingleWakeWordCycle(int sessionId) async {
    if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final String path = '${directory.path}/reminicare_wake_${DateTime.now().millisecondsSinceEpoch}.wav';

        if (_isRecordingOnHardware) {
          await _audioRecorder.stop();
          _isRecordingOnHardware = false;
          if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 150)); // 切換緩衝
        }

        if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) return;

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );
        _isRecordingOnHardware = true;

        await Future.delayed(const Duration(milliseconds: 3500));

        if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) {
          return;
        }

        final String? savedPath = await _audioRecorder.stop();
        if (savedPath == null) {
          debugPrint("❌ [硬體鎖死警告] _audioRecorder.stop() 回傳 null，麥克風錄製失敗！");
        }
        _isRecordingOnHardware = false;
        if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 150)); // 切換緩衝

        if (savedPath != null && _isRollingWakeWord && sessionId == _wakeWordSessionId) {
          _transcribeAndCheckWakeWord(savedPath, sessionId);
        }
      }
    } catch (e) {
      debugPrint("[喚醒器] 輪詢異常: $e");
      _isRecordingOnHardware = false;
      if (_isRollingWakeWord && sessionId == _wakeWordSessionId) {
        Future.delayed(const Duration(seconds: 2), () => _runSingleWakeWordCycle(sessionId));
      }
    }
  }

  Future<void> _transcribeAndCheckWakeWord(String audioPath, int sessionId) async {
    try {
      final String? transcript = await sttService.transcribe(audioPath);
      try { File(audioPath).deleteSync(); } catch (_) {}

      if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) return;

      if (transcript != null) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[喚醒助理] 解析內容: '$cleanText'，完成監聽狀態為: $checkCompletedCommands");

        if (!checkCompletedCommands) {
          if (_matchesCommand(cleanText, ReminiCareConfig.startWakeWords)) {
            debugPrint("🎉 [助理喚醒成功] 開始聊天 (口令: $cleanText)");
            _isRollingWakeWord = false;
            onStartChatFlow?.call();
            return;
          }
        }
        else {
          if (_matchesCommand(cleanText, ReminiCareConfig.restartWakeWords)) {
            debugPrint("🎉 [助理喚醒成功] 重新聊天 (口令: $cleanText)");
            _isRollingWakeWord = false;
            onRestartChatFlow?.call();
            return;
          } else if (_matchesCommand(cleanText, ReminiCareConfig.endWakeWords)) {
            debugPrint("🎉 [助理喚醒成功] 結束聊天 (口令: $cleanText)");
            _isRollingWakeWord = false;
            onEndChatFlow?.call();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("[喚醒器] 翻譯出錯: $e");
    }

    if (_isRollingWakeWord && sessionId == _wakeWordSessionId) {
      _runSingleWakeWordCycle(sessionId);
    }
  }

  // ==========================================
  // 🎙️ 輪詢 B：滾動對話切片累積錄製與 WAV 拼接
  // ==========================================
  Future<void> startChatFlow() async {
    await stopActiveAudioOperations();
    _recordedChunkPaths.clear();
    _isRollingChatRecord = true;
    _chatRecordSessionId++;
    _runSingleChatRecordCycle(_chatRecordSessionId);
  }

  Future<void> _runSingleChatRecordCycle(int sessionId) async {
    if (!_isRollingChatRecord || sessionId != _chatRecordSessionId) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final String path = '${directory.path}/reminicare_chat_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';
        _recordedChunkPaths.add(path);

        if (_isRecordingOnHardware) {
          await _audioRecorder.stop();
          _isRecordingOnHardware = false;
          if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 150)); // 切換緩衝
        }

        if (!_isRollingChatRecord || sessionId != _chatRecordSessionId) return;

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );
        _isRecordingOnHardware = true;

        await Future.delayed(const Duration(milliseconds: 5000));

        if (!_isRollingChatRecord || sessionId != _chatRecordSessionId) {
          return;
        }

        final String? savedPath = await _audioRecorder.stop();
        _isRecordingOnHardware = false;
        if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 150)); // 切換緩衝

        if (savedPath != null && _isRollingChatRecord && sessionId == _chatRecordSessionId) {
          _processChatChunk(savedPath, sessionId);
        }
      }
    } catch (e) {
      debugPrint("[對話錄音] 滾動循環異常: $e");
      _isRecordingOnHardware = false;
      if (_isRollingChatRecord && sessionId == _chatRecordSessionId) {
        Future.delayed(const Duration(seconds: 2), () => _runSingleChatRecordCycle(sessionId));
      }
    }
  }

  Future<void> _processChatChunk(String audioPath, int sessionId) async {
    try {
      final String? transcript = await sttService.transcribe(audioPath);

      if (!_isRollingChatRecord || sessionId != _chatRecordSessionId) {
        try { File(audioPath).deleteSync(); } catch (_) {}
        return;
      }

      if (transcript != null && transcript.trim().isNotEmpty) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[助理錄音中] 段落: '$cleanText'");

        if (_matchesCommand(cleanText, ReminiCareConfig.endWakeWords)) {
          debugPrint("🎉 [結束口令成功] 準備分批拼接 WAV。");
          _isRollingChatRecord = false;

          _recordedChunkPaths.remove(audioPath);
          try { File(audioPath).deleteSync(); } catch (_) {}

          final List<String> mergedWavPaths = await _concatenateWavFiles(_recordedChunkPaths);
          onSpeechCompleted?.call(mergedWavPaths);
          return;
        }
      }
    } catch (e) {
      debugPrint("[助理] 處理切片異常: $e");
    }

    if (_isRollingChatRecord && sessionId == _chatRecordSessionId) {
      _runSingleChatRecordCycle(sessionId);
    }
  }

  Future<void> forceEndChat() async {
    _isRollingChatRecord = false;
    _chatRecordSessionId++;
    try {
      if (_isRecordingOnHardware) {
        await _audioRecorder.stop();
        _isRecordingOnHardware = false;
      }

      final List<String> mergedWavPaths = await _concatenateWavFiles(_recordedChunkPaths);
      onSpeechCompleted?.call(mergedWavPaths);
    } catch (e) {
      debugPrint("[助理] 手動停止失敗: $e");
      onSpeechCompleted?.call([]);
    }
  }

  bool _matchesCommand(String text, List<String> commandList) {
    final String cleanText = text.replaceAll(" ", "");
    for (var cmd in commandList) {
      if (cleanText.contains(cmd)) return true;
    }
    return false;
  }

  WavInfo? _parseWav(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final String riff = String.fromCharCodes(bytes.sublist(0, 4));
    final String wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != "RIFF" || wave != "WAVE") return null;

    int offset = 12;
    int dataChunkSizeOffset = -1;

    while (offset + 8 <= bytes.length) {
      final String chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final int chunkSize = ByteData.sublistView(bytes, offset + 4, offset + 8).getUint32(0, Endian.little);

      if (chunkId == "data") {
        dataChunkSizeOffset = offset + 4;
        final header = bytes.sublist(0, offset + 8);
        final pcm = bytes.sublist(offset + 8);
        return WavInfo(
          header: header.toList(),
          pcm: pcm.toList(),
          dataChunkSizeOffset: dataChunkSizeOffset,
        );
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 != 0) offset += 1;
    }
    return null;
  }

  // 💡 修正 2：將所有切片每 5 個 (因為每個 5 秒，所以是 25 秒) 合併為一個新檔，完美避開 Whisper 的 30 秒極限
  Future<List<String>> _concatenateWavFiles(List<String> paths) async {
    if (paths.isEmpty) return [];
    debugPrint("[WAV 拼接] 正在將 ${paths.length} 個 WAV 段落分批拼接 (每批最多 25 秒)...");

    List<String> outputPaths = [];

    for (int i = 0; i < paths.length; i += 5) {
      int end = (i + 5 < paths.length) ? i + 5 : paths.length;
      List<String> subPaths = paths.sublist(i, end);

      String? mergedChunk = await _mergeWavGroup(subPaths, i);
      if (mergedChunk != null) {
        outputPaths.add(mergedChunk);
      }
    }

    return outputPaths;
  }

  Future<String?> _mergeWavGroup(List<String> paths, int groupIndex) async {
    try {
      final directory = await getTemporaryDirectory();
      final String outputPath = '${directory.path}/reminicare_merged_${DateTime.now().millisecondsSinceEpoch}_$groupIndex.wav';
      final File outputFile = File(outputPath);

      List<int> rawPcmBytes = [];
      List<int>? firstWavHeader;
      int dataChunkSizeOffset = -1;

      for (int i = 0; i < paths.length; i++) {
        final file = File(paths[i]);
        if (!file.existsSync()) continue;

        final bytes = await file.readAsBytes();
        final wavInfo = _parseWav(bytes);
        if (wavInfo == null) continue;

        if (i == 0 || firstWavHeader == null) {
          firstWavHeader = wavInfo.header;
          dataChunkSizeOffset = wavInfo.dataChunkSizeOffset;
        }
        rawPcmBytes.addAll(wavInfo.pcm);
      }

      if (firstWavHeader == null || dataChunkSizeOffset == -1) return null;

      final int totalDataSize = rawPcmBytes.length;
      final int totalFileSize = (firstWavHeader.length - 8) + totalDataSize;
      final ByteData sizeBuffer = ByteData(4);

      sizeBuffer.setUint32(0, totalFileSize, Endian.little);
      firstWavHeader[4] = sizeBuffer.getUint8(0);
      firstWavHeader[5] = sizeBuffer.getUint8(1);
      firstWavHeader[6] = sizeBuffer.getUint8(2);
      firstWavHeader[7] = sizeBuffer.getUint8(3);

      sizeBuffer.setUint32(0, totalDataSize, Endian.little);
      firstWavHeader[dataChunkSizeOffset] = sizeBuffer.getUint8(0);
      firstWavHeader[dataChunkSizeOffset + 1] = sizeBuffer.getUint8(1);
      firstWavHeader[dataChunkSizeOffset + 2] = sizeBuffer.getUint8(2);
      firstWavHeader[dataChunkSizeOffset + 3] = sizeBuffer.getUint8(3);

      final List<int> consolidatedWavBytes = [...firstWavHeader, ...rawPcmBytes];
      await outputFile.writeAsBytes(consolidatedWavBytes);

      return outputPath;
    } catch (e) {
      debugPrint("[WAV 拼接失敗] 群組 $groupIndex 發生異常: $e");
      return null;
    }
  }
}