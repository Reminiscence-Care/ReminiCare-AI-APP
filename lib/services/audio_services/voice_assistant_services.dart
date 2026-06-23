import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:remini_care_ai_app/services/api_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

import 'speech_services.dart';

// =========================================================================
// 🎙️ 💡 獨立語音助手核心控制器 (VoiceAssistantManager)
// 完美整合 iOS PlayAndRecord 音訊模式 + VAD 智慧對話流 + TTS 本機快取
// =========================================================================
class VoiceAssistantManager {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ITTSService ttsService = ApiServices().tts;
  final ISTTService sttService = ApiServices().stt;

  bool _isRollingWakeWord = false;
  bool _isRollingChatRecord = false;
  bool _isRecordingOnHardware = false;

  int _wakeWordSessionId = 0;
  int _chatRecordSessionId = 0;
  int _playSessionId = 0;

  // ==========================================
  // 💾 TTS 持久化快取與容量管理
  // ==========================================
  static String _spKeyTtsCache = ReminiCareConfig.ttsCacheName;
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

  bool _isAudioSessionConfigured = false;

  // ==========================================
  // 🍎 解決 iPad/iOS 播放與錄音衝突的「絕對霸道」設定
  // ==========================================
  Future<void> _ensureAudioSessionConfigured() async {
    if (_isAudioSessionConfigured) return;
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        await AudioPlayer.global.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
        ));
        _isAudioSessionConfigured = true;
        debugPrint("🍎 [AudioSession] 邊播邊錄音軌已全局鎖定！");
      }
    } catch (e) {
      debugPrint("❌ [AudioSession] 鎖定音軌失敗: $e");
    }
  }

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
      _cacheInitialized = true;
    } catch (e) {
      _cacheMetadata = {};
      _cacheInitialized = true;
    }
  }

  Future<void> _saveCacheIndex() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_spKeyTtsCache, jsonEncode(_cacheMetadata));
    } catch (_) {}
  }

  Future<void> _checkAndCleanupCache(int newFileSize) async {
    int currentTotalSize = 0;
    _cacheMetadata.values.forEach((data) {
      currentTotalSize += (data['size'] as int? ?? 0);
    });

    if (currentTotalSize + newFileSize <= _maxCacheSizeBytes) return;

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
      }
    }
    await _saveCacheIndex();
  }

  void forceRecalibrateVad() {
    _isCalibrated = false;
    _calibrationTicks = 0;
    _calibrationSumDb = 0.0;
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
  // 🎙️ 引擎 A：背景喚醒詞檢測 (VAD 智慧過濾)
  // ==========================================
  Future<void> startBackgroundWakeWordCycle() async {
    await stopActiveAudioOperations();
    _isRollingWakeWord = true;
    _wakeWordSessionId++;
    _runSmartWakeWordCycle(_wakeWordSessionId);
  }

  Future<void> _runSmartWakeWordCycle(int sessionId) async {
    if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) return;

    await _ensureAudioSessionConfigured();

    _hasSpoken = false;
    _silenceMs = 0;
    _idleMs = 0;
    _consecutiveLoudTicks = 0;

    try {
      if (await _audioRecorder.hasPermission()) {

        if (Platform.isIOS || Platform.isMacOS) {
          await Future.delayed(const Duration(milliseconds: 300));
        }

        final directory = await getTemporaryDirectory();
        _currentRecordPath = '${directory.path}/reminicare_wake_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: _currentRecordPath!,
        );
        _isRecordingOnHardware = true;

        if (!_isCalibrated) {
          debugPrint("🎛️ [背景 VAD] 啟動環境雜音採樣校正...");
        }

        _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
          if (!_isRecordingOnHardware || !_isRollingWakeWord || sessionId != _wakeWordSessionId) {
            timer.cancel();
            return;
          }

          // 💡 關鍵修復：加入 try-catch 防止計時器觸發時 recorder 已被 dispose 的崩潰問題
          Amplitude amplitude;
          try {
            amplitude = await _audioRecorder.getAmplitude();
          } catch (e) {
            timer.cancel();
            return;
          }

          final currentDb = amplitude.current;

          if (!_isCalibrated) {
            if (currentDb > -100.0) {
              _calibrationSumDb += currentDb;
              _calibrationTicks++;
              if (_calibrationTicks >= 8) {
                double avgNoise = _calibrationSumDb / 8;
                _vadThresholdDb = (avgNoise + 12.0).clamp(-45.0, -20.0);
                _isCalibrated = true;
                debugPrint("🎛️ [VAD 自動校正完成] 房間雜音: ${avgNoise.toStringAsFixed(1)} dB, 門檻: ${_vadThresholdDb.toStringAsFixed(1)} dB");
              }
            }
            return;
          }

          if (currentDb >= _vadThresholdDb) {
            _consecutiveLoudTicks++;
            if (_consecutiveLoudTicks >= 2 && !_hasSpoken) {
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
                timer.cancel();
                await _processWakeWordChunk(_currentRecordPath!, sessionId);
              }
            } else {
              _idleMs += 200;
              if (_idleMs >= _idleTimeoutMs) {
                timer.cancel();
                await _restartWakeWordSilently(sessionId);
              }
            }
          }
        });
      } else {
        debugPrint("❌ 麥克風權限已被拒絕！請前往 iOS 設定開啟。");
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
      final String? transcript = await sttService.transcribe(audioPath);
      try { File(audioPath).deleteSync(); } catch (_) {}

      if (!_isRollingWakeWord || sessionId != _wakeWordSessionId) return;

      if (transcript != null) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[喚醒助理] 解析內容: '$cleanText'");

        onBackgroundTextRecognized?.call(cleanText);

        if (_matchesCommand(cleanText, ReminiCareConfig.restartWakeWords)) {
          _isRollingWakeWord = false;
          onRestartChatFlow?.call();
          return;
        } else if (_matchesCommand(cleanText, ReminiCareConfig.endWakeWords)) {
          _isRollingWakeWord = false;
          onEndChatFlow?.call();
          return;
        } else if (_matchesCommand(cleanText, ReminiCareConfig.startWakeWords)) {
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

    await _ensureAudioSessionConfigured();

    _hasSpoken = false;
    _silenceMs = 0;
    _idleMs = 0;
    _consecutiveLoudTicks = 0;

    try {
      if (await _audioRecorder.hasPermission()) {

        if (Platform.isIOS || Platform.isMacOS) {
          await Future.delayed(const Duration(milliseconds: 300));
        }

        final directory = await getTemporaryDirectory();
        _currentRecordPath = '${directory.path}/reminicare_chat_smart_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: _currentRecordPath!,
        );
        _isRecordingOnHardware = true;

        _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
          if (!_isRecordingOnHardware || !_isRollingChatRecord) {
            timer.cancel();
            return;
          }

          // 💡 關鍵修復：加入 try-catch 防止計時器觸發時 recorder 已被 dispose 的崩潰問題
          Amplitude amplitude;
          try {
            amplitude = await _audioRecorder.getAmplitude();
          } catch (e) {
            timer.cancel();
            return;
          }

          final currentDb = amplitude.current;

          if (!_isCalibrated) {
            if (currentDb > -100.0) {
              _calibrationSumDb += currentDb;
              _calibrationTicks++;
              if (_calibrationTicks >= 8) {
                double avgNoise = _calibrationSumDb / 8;
                _vadThresholdDb = (avgNoise + 12.0).clamp(-45.0, -20.0);
                _isCalibrated = true;
              }
            }
            return;
          }

          if (currentDb >= _vadThresholdDb) {
            _consecutiveLoudTicks++;
            if (_consecutiveLoudTicks >= 2 && !_hasSpoken) {
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
                timer.cancel();
                await forceEndChat();
              }
            } else {
              _idleMs += 200;
              if (_idleMs >= _idleTimeoutMs) {
                timer.cancel();
                await forceEndChat();
              }
            }
          }
        });
      } else {
        debugPrint("❌ 麥克風權限已被拒絕！");
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

  // ==========================================
  // 🔊 TTS 快取與無縫連續播放邏輯
  // ==========================================
  Future<void> stopCurrentPlayback() async {
    _playSessionId++;
    try { await _audioPlayer.stop(); } catch (_) {}
  }

  Future<void> playLanguageSequence({
    required List<String> texts,
    required List<String> languages,
    int repeatCount = 1,
    int gapMs = 300,
    int partGapMs = 150,
  }) async {
    if (texts.isEmpty || kIsWeb || languages.isEmpty || repeatCount <= 0) return;

    final currentSession = ++_playSessionId;

    try {
      await _ensureAudioSessionConfigured();
      await _initCacheIfNeeded();
      final storageDir = await getApplicationDocumentsDirectory();

      for (final text in texts) {
        if (text.isEmpty) continue;
        for (final lang in languages.toSet()) {
          final cacheKey = '$lang::$text';

          if (_ttsCache.containsKey(cacheKey)) {
            _cacheMetadata[cacheKey]?['lastUsed'] = DateTime.now().millisecondsSinceEpoch;
            continue;
          }

          final audioBytes = await ttsService.generateSpeech(text, lang);
          if (audioBytes == null) continue;

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

            if (i < texts.length - 1 && partGapMs > 0) {
              await Future.delayed(Duration(milliseconds: partGapMs));
            }
          }

          if (currentSession != _playSessionId) return;

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