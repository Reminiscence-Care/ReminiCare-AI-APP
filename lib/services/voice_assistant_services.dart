import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

// 💡 引入全域金鑰與 ASR 服務
import 'reminicare_ai_services.dart';

/// 💡 用於動態解析 WAV 音訊區塊的內部資料結構 (成功從 services 檔案抽離)
class WavInfo {
  final List<int> header;          // 包含 data 區塊大小標記之前的完整標頭
  final List<int> pcm;             // 純淨的 PCM 音訊數據
  final int dataChunkSizeOffset;   // data 區塊長度標記在檔案中的精確位元組偏移量

  WavInfo({
    required this.header,
    required this.pcm,
    required this.dataChunkSizeOffset,
  });
}

// =========================================================================
// 🎙️ 💡 獨立語音助手核心控制器 (VoiceAssistantManager) - 獨立成檔
//      封裝了背景喚醒、VAD 滾動切片、WAV 二進位動態無損拼接
// =========================================================================
class VoiceAssistantManager {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final NckuSpeechService _nckuSpeechService = NckuSpeechService();

  bool _isRollingWakeWord = false;
  bool _isRollingChatRecord = false;
  final List<String> _recordedChunkPaths = [];

  // 外部狀態與指示回調事件
  void Function()? onStartChatFlow;
  void Function()? onRestartChatFlow;
  void Function()? onEndChatFlow;
  void Function(String mergedAudioPath)? onSpeechCompleted;

  // 💡 是否需要檢測「重新錄音/結束聊天」完成指令 (預設為 false 僅監聽開始錄音)
  bool checkCompletedCommands = false;

  bool get isListening => _isRollingWakeWord || _isRollingChatRecord;

  /// 一、重置與安全釋放所有語音/錄音資源
  void stopActiveAudioOperations() {
    _isRollingWakeWord = false;
    _isRollingChatRecord = false;
    _audioRecorder.stop();
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
    stopActiveAudioOperations();
    _audioRecorder.dispose();
  }

  // ==========================================
  // 🎙️ 輪詢 A：背景一鍵「喚醒詞」檢測循環 (Rolling Wake-word)
  // ==========================================
  Future<void> startBackgroundWakeWordCycle() async {
    if (_isRollingWakeWord) return;
    _isRollingWakeWord = true;
    _runSingleWakeWordCycle();
  }

  Future<void> _runSingleWakeWordCycle() async {
    if (!_isRollingWakeWord) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final String path = '${directory.path}/reminicare_wake_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );

        // 每隔 3.5 秒錄製一次
        await Future.delayed(const Duration(milliseconds: 3500));
        if (!_isRollingWakeWord) {
          await _audioRecorder.stop();
          return;
        }

        final String? savedPath = await _audioRecorder.stop();
        if (savedPath != null) {
          _transcribeAndCheckWakeWord(savedPath);
        }
      }
    } catch (e) {
      debugPrint("[喚醒器] 輪詢異常: $e");
      if (_isRollingWakeWord) {
        Future.delayed(const Duration(seconds: 2), _runSingleWakeWordCycle);
      }
    }
  }

  Future<void> _transcribeAndCheckWakeWord(String audioPath) async {
    try {
      final String? transcript = await _nckuSpeechService.transcribe(audioPath);
      try { File(audioPath).deleteSync(); } catch (_) {}

      if (transcript != null) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[喚醒助理] 解析內容: '$cleanText'，完成監聽狀態為: $checkCompletedCommands");

        // 1. 如果處於準備/修改準備階段：動態模糊檢測「開始錄音」
        if (!checkCompletedCommands) {
          if (_matchesCommand(cleanText, ReminiCareConfig.startWakeWords)) {
            debugPrint("🎉 [助理喚醒成功] 開始聊天 (口令: $cleanText)");
            _isRollingWakeWord = false;
            onStartChatFlow?.call();
            return;
          }
        }
        // 2. 如果處於完成階段：動態模糊檢測「重新錄音/結束聊天」
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

    if (_isRollingWakeWord) {
      _runSingleWakeWordCycle();
    }
  }

  // ==========================================
  // 🎙️ 輪詢 B：滾動對話切片累積錄製與 WAV 拼接
  // ==========================================
  Future<void> startChatFlow() async {
    stopActiveAudioOperations();
    _recordedChunkPaths.clear();
    _isRollingChatRecord = true;
    _runSingleChatRecordCycle();
  }

  Future<void> _runSingleChatRecordCycle() async {
    if (!_isRollingChatRecord) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final String path = '${directory.path}/reminicare_chat_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';
        _recordedChunkPaths.add(path);

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );

        // 每隔 5 秒無痛錄製一個對話切片
        await Future.delayed(const Duration(milliseconds: 5000));
        if (!_isRollingChatRecord) {
          await _audioRecorder.stop();
          return;
        }

        final String? savedPath = await _audioRecorder.stop();
        if (savedPath != null) {
          _processChatChunk(savedPath);
        }
      }
    } catch (e) {
      debugPrint("[對話錄音] 滾動循環異常: $e");
      if (_isRollingChatRecord) {
        Future.delayed(const Duration(seconds: 2), _runSingleChatRecordCycle);
      }
    }
  }

  Future<void> _processChatChunk(String audioPath) async {
    try {
      final String? transcript = await _nckuSpeechService.transcribe(audioPath);

      if (transcript != null && transcript.trim().isNotEmpty) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[助理錄音中] 段落: '$cleanText'");

        // 偵測到使用者講了結束語，開啟二進位 WAV 合成
        if (_matchesCommand(cleanText, ReminiCareConfig.endWakeWords)) {
          debugPrint("🎉 [結束口令成功] 準備拼接 WAV。");
          _isRollingChatRecord = false;

          _recordedChunkPaths.remove(audioPath);
          try { File(audioPath).deleteSync(); } catch (_) {}

          final String? mergedWavPath = await _concatenateWavFiles(_recordedChunkPaths);
          if (mergedWavPath != null) {
            onSpeechCompleted?.call(mergedWavPath);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("[助理錄音] 翻譯切片出錯: $e");
    }

    if (_isRollingChatRecord) {
      _runSingleChatRecordCycle();
    }
  }

  /// 三、手動按鈕結束錄音，直接觸發 WAV 拼接並發送
  Future<void> forceEndChat() async {
    _isRollingChatRecord = false;
    try {
      final String? path = await _audioRecorder.stop();
      if (path != null) {
        final String? mergedWavPath = await _concatenateWavFiles(_recordedChunkPaths);
        if (mergedWavPath != null) {
          onSpeechCompleted?.call(mergedWavPath);
        }
      }
    } catch (e) {
      debugPrint("[助理] 手動停止失敗: $e");
    }
  }

  // 💡 模糊指令比對演算法
  bool _matchesCommand(String text, List<String> commandList) {
    final String cleanText = text.replaceAll(" ", "");
    for (var cmd in commandList) {
      if (cleanText.contains(cmd)) return true;
    }
    return false;
  }

  // 💡 WAV 二進位無損拼接演算法 (動態探測，解決 Format 破壞)
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

  Future<String?> _concatenateWavFiles(List<String> paths) async {
    if (paths.isEmpty) return null;
    debugPrint("[WAV 拼接] 正在無損動態解析並拼接 ${paths.length} 個 WAV 段落...");

    try {
      final directory = await getTemporaryDirectory();
      final String outputPath = '${directory.path}/reminicare_merged_final_${DateTime.now().millisecondsSinceEpoch}.wav';
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
      debugPrint("[WAV 拼接失敗] 發生異常: $e");
      return null;
    }
  }
}