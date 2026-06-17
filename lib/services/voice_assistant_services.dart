import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

import 'speech_services.dart';

// =========================================================================
// 🎙️ 💡 獨立語音助手核心控制器 (VoiceAssistantManager)
// 【全 VAD 雙引擎進化版】背景喚醒與聊天皆使用智慧音量斷句，大幅減少硬體開銷！
// =========================================================================
class VoiceAssistantManager {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ISTTService sttService = YatingSpeechService();

  bool _isRollingWakeWord = false;
  bool _isRollingChatRecord = false;

  bool _isRecordingOnHardware = false;

  int _wakeWordSessionId = 0;
  int _chatRecordSessionId = 0;

  // --- VAD (音量偵測) 核心參數 ---
  final double _vadThresholdDb = -35.0;
  final int _silenceThresholdMs = 2500;
  final int _idleTimeoutMs = 15000;

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

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        _currentRecordPath = '${directory.path}/reminicare_wake_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: _currentRecordPath!,
        );
        _isRecordingOnHardware = true;

        debugPrint("👂 [背景 VAD] 正在監聽口令...");

        _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
          if (!_isRecordingOnHardware || !_isRollingWakeWord || sessionId != _wakeWordSessionId) {
            timer.cancel();
            return;
          }

          final amplitude = await _audioRecorder.getAmplitude();
          final currentDb = amplitude.current;

          if (currentDb >= _vadThresholdDb) {
            if (!_hasSpoken) {
              debugPrint("🗣️ [背景 VAD] 偵測到聲音！(音量: ${currentDb.toStringAsFixed(1)} dB)");
              _hasSpoken = true;
            }
            _silenceMs = 0;
            _idleMs = 0;
          }
          else {
            if (_hasSpoken) {
              _silenceMs += 200;
              if (_silenceMs >= _silenceThresholdMs) {
                // 💡 講完話了，斷句並送交辨識
                debugPrint("🔇 [背景 VAD] 聲音結束，開始辨識口令！");
                timer.cancel();
                await _processWakeWordChunk(_currentRecordPath!, sessionId);
              }
            } else {
              _idleMs += 200;
              if (_idleMs >= _idleTimeoutMs) {
                // 💡 15秒都沒人講話，為防止音檔無限肥大，默默重啟一局 (不送API)
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

        // 💡 修正：無論 checkCompletedCommands 為何，只要辨識到指令就執行
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

    // 💡 如果解析出來發現「不是口令」，就立刻重啟背景監聽
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

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        _currentRecordPath = '${directory.path}/reminicare_chat_smart_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
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

          if (currentDb >= _vadThresholdDb) {
            if (!_hasSpoken) {
              debugPrint("🗣️ [聊天 VAD] 偵測到開始說話！(音量: ${currentDb.toStringAsFixed(1)} dB)");
              _hasSpoken = true;
            }
            _silenceMs = 0;
            _idleMs = 0;
          }
          else {
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
}