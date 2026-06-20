import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

import 'speech_services.dart';

// =========================================================================
// 🎙️ 💡 獨立語音助手核心控制器 (VoiceAssistantManager)
// 【專業 VAD 版】自動測量環境雜音 + 防突發噪音 + 靜音掛斷 + 背景文字廣播
// =========================================================================
class VoiceAssistantManager {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ITTSService ttsService = YatingSpeechService();
  final ISTTService sttService = YatingSpeechService();

  bool _isRollingWakeWord = false;
  bool _isRollingChatRecord = false;
  bool _isRecordingOnHardware = false;

  int _wakeWordSessionId = 0;
  int _chatRecordSessionId = 0;

  int _playSessionId = 0;

  // ==========================================
  // 💾 TTS 持久化快取與容量管理
  // ==========================================
  static const String _spKeyTtsCache = "tts_audio_cache_index_v1";
  static const int _maxCacheSizeBytes = 100 * 1024 * 1024; // 預設 100MB

  bool _cacheInitialized = false;
  final Map<String, File> _ttsCache = {};
  Map<String, dynamic> _cacheMetadata = {};

  void Function(String language)? onPlayingLanguageChanged;
  void Function(String recognizedText)? onBackgroundTextRecognized;

  // ==========================================
  // 🎛️ VAD (音量偵測) 動態校正與防錯參數
  // ==========================================
  double _vadThresholdDb = -35.0;
  final int _silenceThresholdMs = 2500;
  final int _idleTimeoutMs = 15000;

  bool _isCalibrated = false;
  int _calibrationTicks = 0;
  double _calibrationSumDb = 0.0;
  int _consecutiveLoudTicks = 0;

  Timer? _vadTimer;
  int _silenceMs = 0;
  int _idleMs = 0;
  bool _hasSpoken = false;
  String? _currentRecordPath;

  void Function()? onStartChatFlow;
  void Function()? onRestartChatFlow;
  void Function()? onEndChatFlow;
  void Function(List<String> mergedAudioPaths)? onSpeechCompleted;

  bool checkCompletedCommands = false;
  bool get isListening => _isRollingWakeWord || _isRollingChatRecord;

  // ==========================================
  // 🛠️ 初始化與快取管理邏輯
  // ==========================================
  Future<void> _initCacheIfNeeded() async {
    if (_cacheInitialized) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final String? jsonStr = sp.getString(_spKeyTtsCache);

      if (jsonStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        _cacheMetadata = decoded;

        _cacheMetadata.forEach((key, data) {
          final String path = data['path'];
          final file = File(path);
          if (file.existsSync()) _ttsCache[key] = file;
        });

        _cacheMetadata.removeWhere((key, _) => !_ttsCache.containsKey(key));
      }
      debugPrint("📦 [TTS 快取] 已初始化，現有項目: ${_ttsCache.length} 個");
      _cacheInitialized = true;
    } catch (e) {
      debugPrint("[TTS 快取] 初始化失敗: $e");
      _cacheMetadata = {};
      _cacheInitialized = true;
    }
  }

  Future<void> _saveCacheIndex() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_spKeyTtsCache, jsonEncode(_cacheMetadata));
    } catch (e) {
      debugPrint("[TTS 快取] 儲存索引失敗: $e");
    }
  }

  Future<void> _checkAndCleanupCache(int newFileSize) async {
    int currentTotalSize = 0;
    _cacheMetadata.values.forEach((data) {
      currentTotalSize += (data['size'] as int? ?? 0);
    });

    if (currentTotalSize + newFileSize <= _maxCacheSizeBytes) return;

    debugPrint("🧹 [TTS 快取] 容量超出限制，開始清理舊檔案...");
    final sortedKeys = _cacheMetadata.keys.toList()
      ..sort((a, b) {
        final lastA = _cacheMetadata[a]?['lastUsed'] ?? 0;
        final lastB = _cacheMetadata[b]?['lastUsed'] ?? 0;
        return lastA.compareTo(lastB);
      });

    for (final key in sortedKeys) {
      if (currentTotalSize + newFileSize <= _maxCacheSizeBytes * 0.8) break;

      final data = _cacheMetadata[key];
      if (data != null) {
        final int size = data['size'] ?? 0;
        final file = _ttsCache[key];
        if (file != null && file.existsSync()) {
          try { file.deleteSync(); } catch (_) {}
        }
        _ttsCache.remove(key);
        _cacheMetadata.remove(key);
        currentTotalSize -= size;
        debugPrint("🗑️ 已刪除舊快取: $key");
      }
    }
    await _saveCacheIndex();
  }

  void forceRecalibrateVad() {
    _isCalibrated = false;
    _calibrationTicks = 0;
    _calibrationSumDb = 0.0;
    debugPrint("🎛️ [VAD] 已重置校正狀態，將於下次錄音時重新測量環境雜音。");
  }

  Future<void> stopActiveAudioOperations() async {
    _isRollingWakeWord = false;
    _isRollingChatRecord = false;
    _wakeWordSessionId++;
    _chatRecordSessionId++;

    _vadTimer?.cancel();
    _vadTimer = null;

    try {
      if (_isRecordingOnHardware) {
        await _audioRecorder.stop();
        _isRecordingOnHardware = false;
        if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint("[助理] 停止錄音硬體釋放異常: $e");
    }
  }

  void dispose() {
    stopActiveAudioOperations();
    _audioRecorder.dispose();
  }

  // ==========================================
  // 🎙️ 引擎 A：背景喚醒詞檢測 (升級為 VAD 智慧過濾)
  // ==========================================
  Future<void> startBackgroundWakeWordCycle() async {
    await stopActiveAudioOperations();
    _isRollingWakeWord = true;
    _wakeWordSessionId++;
    _runSmartWakeWordCycle(_wakeWordSessionId);
  }

  Future<void> _runSmartWakeWordCycle(int sessionId) async {
    if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) return;

    _hasSpoken = false;
    _silenceMs = 0;
    _idleMs = 0;
    _consecutiveLoudTicks = 0;

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        _currentRecordPath = '${directory.path}/reminicare_wake_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: _currentRecordPath!,
        );
        _isRecordingOnHardware = true;

        if (_isCalibrated) {
          debugPrint("👂 [背景 VAD] 正在監聽口令...");
        } else {
          debugPrint("🎛️ [背景 VAD] 啟動環境雜音採樣校正 (約需 1.6 秒)...");
        }

        _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
          if (!_isRecordingOnHardware || !_isRollingWakeWord || sessionId != _wakeWordSessionId) {
            timer.cancel();
            return;
          }

          final amplitude = await _audioRecorder.getAmplitude();
          final currentDb = amplitude.current;

          if (!_isCalibrated) {
            if (currentDb > -100.0) {
              _calibrationSumDb += currentDb;
              _calibrationTicks++;
              if (_calibrationTicks >= 8) {
                double avgNoise = _calibrationSumDb / 8;
                _vadThresholdDb = (avgNoise + 12.0).clamp(-45.0, -20.0);
                _isCalibrated = true;
                debugPrint("🎛️ [VAD 自動校正完成] 房間雜音: ${avgNoise.toStringAsFixed(1)} dB, 門檻設為: ${_vadThresholdDb.toStringAsFixed(1)} dB");
                debugPrint("👂 [背景 VAD] 開始監聽口令...");
              }
            }
            return;
          }

          if (currentDb >= _vadThresholdDb) {
            _consecutiveLoudTicks++;
            if (_consecutiveLoudTicks >= 2 && !_hasSpoken) {
              debugPrint("🗣️ [背景 VAD] 偵測到聲音！(音量: ${currentDb.toStringAsFixed(1)} dB)");
              _hasSpoken = true;
            }
            if (_hasSpoken) {
              _silenceMs = 0;
              _idleMs = 0;
            }
          } else {
            _consecutiveLoudTicks = 0;

            if (_hasSpoken) {
              _silenceMs += 200;
              if (_silenceMs >= _silenceThresholdMs) {
                debugPrint("🔇 [背景 VAD] 聲音結束，開始辨識口令！");
                timer.cancel();
                await _processWakeWordChunk(_currentRecordPath!, sessionId);
              }
            } else {
              _idleMs += 200;
              if (_idleMs >= _idleTimeoutMs) {
                debugPrint("💤 [背景 VAD] 15秒無聲，清理暫存並重啟監聽。");
                timer.cancel();
                await _restartWakeWordSilently(sessionId);
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint("[喚醒器] VAD 啟動異常: $e");
      _isRecordingOnHardware = false;
      if (_isRollingWakeWord && sessionId == _wakeWordSessionId) {
        Future.delayed(const Duration(seconds: 2), () => _runSmartWakeWordCycle(sessionId));
      }
    }
  }

  Future<void> _restartWakeWordSilently(int sessionId) async {
    if (_isRecordingOnHardware) {
      await _audioRecorder.stop();
      _isRecordingOnHardware = false;
    }
    if (_currentRecordPath != null) {
      try { File(_currentRecordPath!).deleteSync(); } catch (_) {}
    }
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 150));
    _runSmartWakeWordCycle(sessionId);
  }

  Future<void> _processWakeWordChunk(String audioPath, int sessionId) async {
    if (_isRecordingOnHardware) {
      await _audioRecorder.stop();
      _isRecordingOnHardware = false;
    }
    if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 150));

    try {
      debugPrint("🔍 [背景 VAD] 送交 ASR 分析...");
      final String? transcript = await sttService.transcribe(audioPath);
      try { File(audioPath).deleteSync(); } catch (_) {}

      if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) return;

      if (transcript != null) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[喚醒助理] 解析內容: '$cleanText'，完成監聽狀態為: $checkCompletedCommands");

        onBackgroundTextRecognized?.call(cleanText);

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
        } else if (_matchesCommand(cleanText, ReminiCareConfig.startWakeWords)) {
          debugPrint("🎉 [助理喚醒成功] 開始聊天 (口令: $cleanText)");
          _isRollingWakeWord = false;
          onStartChatFlow?.call();
          return;
        }
      }
    } catch (e) {
      debugPrint("[喚醒器] 翻譯出錯: $e");
    }

    if (_isRollingWakeWord && sessionId == _wakeWordSessionId) {
      _runSmartWakeWordCycle(sessionId);
    }
  }

  bool _matchesCommand(String text, List<String> commandList) {
    final String cleanText = text.replaceAll(" ", "");
    for (var cmd in commandList) {
      if (cleanText.contains(cmd)) return true;
    }
    return false;
  }

  // ==========================================
  // 🎙️ 引擎 B：智慧語音對話流 (聊天室模式 VAD)
  // ==========================================
  Future<void> startChatFlow() async {
    await stopActiveAudioOperations();
    _isRollingChatRecord = true;
    _chatRecordSessionId++;

    _hasSpoken = false;
    _silenceMs = 0;
    _idleMs = 0;
    _consecutiveLoudTicks = 0;

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        _currentRecordPath = '${directory.path}/reminicare_chat_smart_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: _currentRecordPath!,
        );
        _isRecordingOnHardware = true;

        debugPrint("🎤 [聊天 VAD] 開始智慧聊天錄音監聽...");

        _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
          if (!_isRecordingOnHardware || !_isRollingChatRecord || timer.tick == 0) {
            timer.cancel();
            return;
          }

          final amplitude = await _audioRecorder.getAmplitude();
          final currentDb = amplitude.current;

          if (!_isCalibrated) {
            if (currentDb > -100.0) {
              _calibrationSumDb += currentDb;
              _calibrationTicks++;
              if (_calibrationTicks >= 8) {
                double avgNoise = _calibrationSumDb / 8;
                _vadThresholdDb = (avgNoise + 12.0).clamp(-45.0, -20.0);
                _isCalibrated = true;
                debugPrint("🎛️ [聊天 VAD 自動校正完成] 房間雜音: ${avgNoise.toStringAsFixed(1)} dB, 講話門檻設為: ${_vadThresholdDb.toStringAsFixed(1)} dB");
              }
            }
            return;
          }

          if (currentDb >= _vadThresholdDb) {
            _consecutiveLoudTicks++;
            if (_consecutiveLoudTicks >= 2 && !_hasSpoken) {
              debugPrint("🗣️ [聊天 VAD] 偵測到真實語音開始！(音量: ${currentDb.toStringAsFixed(1)} dB)");
              _hasSpoken = true;
            }
            if (_hasSpoken) {
              _silenceMs = 0;
              _idleMs = 0;
            }
          }
          else {
            _consecutiveLoudTicks = 0;

            if (_hasSpoken) {
              _silenceMs += 200;
              if (_silenceMs >= _silenceThresholdMs) {
                debugPrint("🔇 [聊天 VAD] 偵測到連續 ${_silenceThresholdMs/1000} 秒靜音，判斷句子結束，自動停止！");
                timer.cancel();
                await forceEndChat();
              }
            } else {
              _idleMs += 200;
              if (_idleMs >= _idleTimeoutMs) {
                debugPrint("💤 [聊天 VAD] 使用者連續 ${_idleTimeoutMs/1000} 秒未發言，自動超時停止。");
                timer.cancel();
                await forceEndChat();
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint("[智慧對話錄音] 啟動異常: $e");
      _isRecordingOnHardware = false;
    }
  }

  Future<void> forceEndChat() async {
    _isRollingChatRecord = false;
    _chatRecordSessionId++;

    _vadTimer?.cancel();
    _vadTimer = null;

    try {
      if (_isRecordingOnHardware) {
        await _audioRecorder.stop();
        _isRecordingOnHardware = false;
        if (!kIsWeb) await Future.delayed(const Duration(milliseconds: 300));
      }

      if (_currentRecordPath != null && File(_currentRecordPath!).existsSync()) {
        onSpeechCompleted?.call([_currentRecordPath!]);
      } else {
        onSpeechCompleted?.call([]);
      }
    } catch (e) {
      debugPrint("[助理] 結束錄音失敗: $e");
      onSpeechCompleted?.call([]);
    }
  }

  Future<void> stopCurrentPlayback() async {
    _playSessionId++;
    try { await _audioPlayer.stop(); } catch (_) {}
  }

  // 💡 關鍵改變：接收 List<String> texts，實現切段合成，完美增加 Cache 命中率！
  Future<void> playLanguageSequence({
    required List<String> texts,
    required List<String> languages,
    int repeatCount = 1,
    int gapMs = 300,
    int partGapMs = 150, // 💡 新增：同語言內「長輩」與「問題」之間的微小停頓
  }) async {
    if (texts.isEmpty || kIsWeb || languages.isEmpty || repeatCount <= 0) return;

    final currentSession = ++_playSessionId;

    try {
      await _initCacheIfNeeded();
      final storageDir = await getApplicationDocumentsDirectory();

      // 1. 批次建立所有片段的快取
      for (final text in texts) {
        if (text.isEmpty) continue;
        for (final lang in languages.toSet()) {
          final cacheKey = '$lang::$text';

          if (_ttsCache.containsKey(cacheKey)) {
            _cacheMetadata[cacheKey]?['lastUsed'] = DateTime.now().millisecondsSinceEpoch;
            continue;
          }

          final audioBytes = await ttsService.generateSpeech(text, lang);
          if (audioBytes == null) {
            debugPrint('[TTS失敗] $lang - $text');
            continue;
          }

          final safeLang = switch (lang) {
            "台語" => "tw",
            "中文" => "zh",
            _ => lang,
          };

          final fileSize = audioBytes.length;
          await _checkAndCleanupCache(fileSize);

          final fileName = 'tts_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav';
          final file = File('${storageDir.path}/$fileName');

          await file.writeAsBytes(audioBytes, flush: true);

          _ttsCache[cacheKey] = file;
          _cacheMetadata[cacheKey] = {
            "path": file.path,
            "lastUsed": DateTime.now().millisecondsSinceEpoch,
            "size": fileSize,
          };

          await _saveCacheIndex();
        }
      }

      // 2. 依照切段順序播放，達成無縫連播
      for (int repeat = 0; repeat < repeatCount; repeat++) {
        for (final lang in languages) {
          if (currentSession != _playSessionId) return;
          onPlayingLanguageChanged?.call(lang);

          for (int i = 0; i < texts.length; i++) {
            final text = texts[i];
            if (text.isEmpty) continue;
            if (currentSession != _playSessionId) return;

            final cacheKey = '$lang::$text';
            final file = _ttsCache[cacheKey];
            if (file == null) continue;

            final completer = Completer<void>();
            final subscription = _audioPlayer.onPlayerComplete.listen((_) {
              if (!completer.isCompleted) completer.complete();
            });

            await _audioPlayer.play(DeviceFileSource(file.path));
            await completer.future;
            await subscription.cancel();

            if (currentSession != _playSessionId) return;

            // 💡 短停頓：在「王阿嬤」跟「小時候...」之間模擬講話呼吸感
            if (i < texts.length - 1 && partGapMs > 0) {
              await Future.delayed(Duration(milliseconds: partGapMs));
            }
          }

          if (currentSession != _playSessionId) return;

          // 換語言時的長停頓
          if (gapMs > 0) {
            await Future.delayed(Duration(milliseconds: gapMs));
          }
        }
      }
    } catch (e) {
      debugPrint('[播放語音序列失敗] $e');
    }
  }
}