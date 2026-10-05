import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'ncku_segmented_stt.dart';
import 'stt_result.dart';
import 'wav_audio.dart';

// =========================================================================
// 💡 1. 定義通用的語音辨識 (STT) 介面
// =========================================================================
abstract class ISTTService {
  /// 傳入本機音檔路徑，回傳辨識後的文字
  Future<String?> transcribe(String audioFilePath);
}

extension SttResultService on ISTTService {
  Future<SttResult> transcribeResult(String path) async {
    try {
      return SttResult(text: await transcribe(path) ?? '');
    } on SttException catch (error) {
      return SttResult(error: error);
    } catch (_) {
      return const SttResult(
        error: SttException(SttErrorKind.network, '語音辨識失敗，請重試。'),
      );
    }
  }
}

// =========================================================================
// 💡 2. 定義通用的語音合成 (TTS) 介面
// =========================================================================
abstract class ITTSService {
  /// 傳入文字與語言，回傳可播放的 Wav 音訊位元組
  Future<Uint8List?> generateSpeech(String text, String language);
}

// =========================================================================
// 🎙️ 3. 成大自研語音服務 (100% 完美接合 NCKU ASR & VITS TCP-TTS)
// =========================================================================
class NckuSpeechService
    implements ISTTService, ITTSService, ProgressSttService {
  final _segmented = NckuSegmentedStt(
    token: () => ReminiCareConfig.nckuSttToken,
  );
  @override
  void Function(int, int)? get onProgress => _segmented.onProgress;
  @override
  set onProgress(void Function(int, int)? value) =>
      _segmented.onProgress = value;
  @override
  void forget(String path) => _segmented.forget(path);
  final String _ttsHost = '140.116.245.146';
  final int _ttsPort = 9998;
  final String _ttsEndOfTransmission = 'EOT';
  final String _ttsApiId = '10012';

  /// 一、成大自研語音辨識服務 (STT)
  @override
  Future<String?> transcribe(String audioFilePath) async {
    if (kIsWeb) {
      throw const SttException(SttErrorKind.invalidAudio, 'Web 不支援錄音檔辨識。');
    }
    return _segmented.transcribe(audioFilePath);
  }

  /// 二、成大自研語音合成服務 (TTS)
  @override
  Future<Uint8List?> generateSpeech(String text, String language) async {
    if (kIsWeb) {
      debugPrint("[NCKU TTS] 瀏覽器 Web 安全限制不支援直接通訊。");
      return null;
    }
    if (text.isEmpty) {
      debugPrint("[NCKU TTS] ❌ 傳入的文字不能為空");
      return null;
    }
    if (text.contains('@@@')) {
      debugPrint("[NCKU TTS] ❌ 傳入的文字不能含有分隔符 '@@@'");
      return null;
    }

    final String langCode = (language == "台語") ? "tw" : "zh";
    final String speaker = (language == "台語") ? "M04" : "4793";
    final String token = ReminiCareConfig.nckuTtsToken;

    debugPrint("[NCKU TTS] 正在建立與 VITS-TCP Server 的連線: $_ttsHost:$_ttsPort");

    try {
      final Socket socket = await Socket.connect(
        _ttsHost,
        _ttsPort,
        timeout: const Duration(seconds: 5),
      );
      final String message =
          "$_ttsApiId@@@$token@@@$langCode@@@$speaker@@@$text$_ttsEndOfTransmission";

      socket.add(utf8.encode(message));
      await socket.flush();

      final List<int> responseBytes = [];
      final Completer<Uint8List?> completer = Completer<Uint8List?>();

      socket.listen(
        (chunk) => responseBytes.addAll(chunk),
        onDone: () {
          try {
            final String resultString = utf8.decode(responseBytes);
            if (resultString.isEmpty) {
              completer.complete(null);
              return;
            }

            final Map<String, dynamic> response =
                jsonDecode(resultString) as Map<String, dynamic>;

            if (response["status"] == true) {
              final String base64Wav = response["bytes"] ?? "";
              final Uint8List wavBytes = base64Decode(base64Wav);

              debugPrint("✅ [NCKU TTS 成功] 語音合成流加載完成。");
              completer.complete(wavBytes);
            } else {
              final String error =
                  response["message"] ?? response["Message"] ?? "Unknown Error";
              debugPrint("❌ [NCKU TTS 伺服器錯誤]: $error");
              completer.complete(null);
            }
          } catch (e) {
            completer.completeError(e);
          }
        },
        onError: (e) => completer.completeError(e),
        cancelOnError: true,
      );

      final Uint8List? audioData = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('成大 TTS 伺服器接收超時'),
      );

      await socket.close();
      socket.destroy();

      return audioData;
    } catch (e) {
      debugPrint("❌ [NCKU TTS 致命錯誤]: $e");
      return null;
    }
  }
}

// =========================================================================
// 🎙️ 4. 雅婷即時語音服務 (Yating Real-time ASR) 實作 STT
// =========================================================================
class YatingSttService implements ISTTService {
  final String _tokenUrl = 'https://asr.api.yating.tw/v1/token';
  final String _wsBaseUrl = 'wss://asr.api.yating.tw/ws/v1/';

  // 💡 升級：不只提取 PCM，還同時解析 fmt chunk 以驗證 WAV 格式！
  Uint8List _extractAndValidatePcmFromWav(Uint8List bytes) =>
      WavAudio.parse(bytes).pcm;

  @override
  Future<String?> transcribe(String audioFilePath) async {
    if (kIsWeb) {
      throw const SttException(SttErrorKind.invalidAudio, '無法讀取音訊或建立語音辨識連線。');
    }

    debugPrint("\n========== [Yating STT Debug 開始] ==========");
    debugPrint("[Yating STT Debug] 📁 準備處理音檔: $audioFilePath");
    WebSocket? connection;
    Timer? eofTimer;

    try {
      final file = File(audioFilePath);
      if (!await file.exists()) {
        throw const SttException(SttErrorKind.invalidAudio, '找不到錄音檔。');
      }

      final bytes = await file.readAsBytes();
      if (bytes.length <= 44) {
        debugPrint("[Yating STT Debug] ❌ 致命錯誤：音檔過小，代表麥克風錄製到空音軌。");
        throw const SttException(SttErrorKind.invalidAudio, '無法讀取音訊或建立語音辨識連線。');
      }

      // 💡 使用新的驗證方法
      final pcmBytes = _extractAndValidatePcmFromWav(bytes);
      if (pcmBytes.isEmpty) {
        debugPrint("[Yating STT Debug] ❌ 提取 PCM 或格式驗證失敗，終止辨識。");
        throw const SttException(SttErrorKind.invalidAudio, '無法讀取音訊或建立語音辨識連線。');
      }

      final tokenResponse = await http
          .post(
            Uri.parse(_tokenUrl),
            headers: {
              'key': ReminiCareConfig.yatingApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({"pipeline": "asr-zh-tw-std"}),
          )
          .timeout(const Duration(seconds: 10));

      if (tokenResponse.statusCode != 201) {
        throw const SttException(SttErrorKind.authentication, '雅婷 STT 驗證失敗。');
      }
      final tokenData = jsonDecode(tokenResponse.body);
      if (tokenData['success'] != true || tokenData['auth_token'] == null) {
        throw const SttException(SttErrorKind.invalidAudio, '無法讀取音訊或建立語音辨識連線。');
      }

      final ws = await WebSocket.connect(
        '$_wsBaseUrl?token=${tokenData['auth_token']}',
      );
      connection = ws;
      final completer = Completer<String?>();
      completer.future.ignore();
      var allAudioSent = false;

      String fullTranscript = "";
      String currentSentence = "";
      bool isReadyToSend = false;

      ws.listen(
        (message) async {
          if (message is String) {
            final data = jsonDecode(message);
            if (data['status'] == 'error') {
              debugPrint("[ASR LISTEN ERROR]");
              if (!completer.isCompleted) {
                completer.completeError(
                  const SttException(SttErrorKind.server, '雅婷辨識服務回報錯誤。'),
                );
              }
              ws.close();
              return;
            }

            if (data['status'] == 'ok') isReadyToSend = true;

            if (data['pipe'] != null) {
              debugPrint(
                "\n============================= [ASR DATA] =============================",
              );

              debugPrint(
                "============================= [ASR DATA] =============================\n",
              );
              final pipe = data['pipe'];
              if (pipe['asr_sentence'] != null) {
                currentSentence = pipe['asr_sentence'];
              }

              if (pipe['asr_final'] == true) {
                fullTranscript += "$currentSentence，";
                currentSentence = "";
              }

              if (pipe['asr_state'] == 'asr_eof') {
                if (!completer.isCompleted) {
                  completer.complete(fullTranscript + currentSentence);
                  ws.close();
                }
              }
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.completeError(
              const SttException(SttErrorKind.network, '雅婷辨識連線失敗。'),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            if (allAudioSent) {
              completer.complete(fullTranscript + currentSentence);
            } else {
              completer.completeError(
                const SttException(SttErrorKind.network, '語音傳送中斷，請重試。'),
              );
            }
          }
        },
      );

      int waitReadyCount = 0;
      while (!isReadyToSend && waitReadyCount < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitReadyCount++;
      }

      if (!isReadyToSend) {
        ws.close();
        throw const SttException(SttErrorKind.timeout, '雅婷辨識服務未就緒，請重試。');
      }

      final int chunkSize = 2000;
      for (int i = 0; i < pcmBytes.length; i += chunkSize) {
        if (ws.readyState != WebSocket.open) break;
        int end = (i + chunkSize < pcmBytes.length)
            ? i + chunkSize
            : pcmBytes.length;
        ws.add(pcmBytes.sublist(i, end));

        // 💡 升級修復：依照官方建議 Streaming 速率，精準控速為 62500 微秒 (62.5ms)
        await Future.delayed(const Duration(microseconds: 62500));
      }

      if (ws.readyState == WebSocket.open) {
        allAudioSent = true;
        ws.add(Uint8List(0));
      }

      Timer eofFallbackTimer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) {
          debugPrint("[Yating STT Debug] ⏱️ 伺服器已讀取完畢但未回傳 asr_eof (靜音裝死)，強制結算！");
          completer.complete(fullTranscript + currentSentence);
          ws.close();
        }
      });
      eofTimer = eofFallbackTimer;

      final String? finalTranscription = await completer.future;
      eofFallbackTimer.cancel();

      String cleanedTranscription =
          finalTranscription?.replaceAll(RegExp(r'^[，\s]+|[，\s]+$'), '') ?? "";

      debugPrint("========== [Yating STT Debug 結束] ==========\n");

      return cleanedTranscription.isNotEmpty
          ? cleanedTranscription.trim()
          : null;
    } on SttException {
      rethrow;
    } on TimeoutException {
      throw const SttException(SttErrorKind.timeout, '雅婷語音辨識逾時。');
    } on FormatException {
      throw const SttException(SttErrorKind.invalidAudio, '錄音或辨識回應格式不正確。');
    } catch (_) {
      throw const SttException(SttErrorKind.network, '雅婷語音辨識失敗，請重試。');
    } finally {
      eofTimer?.cancel();
      await connection?.close();
    }
  }
}

// =========================================================================
// 🎙️ 5. 雅婷語音合成服務 (Yating TTS v2) 實作 TTS
// =========================================================================
class YatingTtsService implements ITTSService {
  final String _ttsUrl = 'https://tts.api.yating.tw/v2/speeches/short';

  // 💡 關鍵修復：手動補上標準的 44 bytes WAV 檔頭 (16kHz, 單聲道, 16-bit)
  Uint8List _addWavHeader(Uint8List pcmData) {
    final int channels = 1;
    final int sampleRate = 16000; // Yating TTS 回傳的是 16K
    final int byteRate = sampleRate * channels * 2; // 16-bit = 2 bytes

    final ByteData header = ByteData(44);

    // 'RIFF' chunk
    header.setUint8(0, 82);
    header.setUint8(1, 73);
    header.setUint8(2, 70);
    header.setUint8(3, 70);
    header.setUint32(4, 36 + pcmData.length, Endian.little);

    // 'WAVE' format
    header.setUint8(8, 87);
    header.setUint8(9, 65);
    header.setUint8(10, 86);
    header.setUint8(11, 69);

    // 'fmt ' subchunk
    header.setUint8(12, 102);
    header.setUint8(13, 109);
    header.setUint8(14, 116);
    header.setUint8(15, 32);
    header.setUint32(16, 16, Endian.little); // PCM size
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little); // BlockAlign
    header.setUint16(34, 16, Endian.little); // BitsPerSample

    // 'data' subchunk
    header.setUint8(36, 100);
    header.setUint8(37, 97);
    header.setUint8(38, 116);
    header.setUint8(39, 97);
    header.setUint32(40, pcmData.length, Endian.little);

    final BytesBuilder builder = BytesBuilder();
    builder.add(header.buffer.asUint8List());
    builder.add(pcmData);
    return builder.toBytes();
  }

  @override
  Future<Uint8List?> generateSpeech(String text, String language) async {
    if (text.isEmpty) return null;
    final String model = (language == "台語") ? "tai_female_1" : "zh_en_female_1";

    try {
      final Map<String, dynamic> requestBody = {
        "input": {"text": text, "type": "text"},
        "voice": {"model": model, "speed": 1.0, "pitch": 1.0, "energy": 1.0},
        // 我們要求 16K 的 Raw PCM 數據
        "audioConfig": {"encoding": "LINEAR16", "sampleRate": "16K"},
      };

      final response = await http
          .post(
            Uri.parse(_ttsUrl),
            headers: {
              'Content-Type': 'application/json',
              'key': ReminiCareConfig.yatingApiKey,
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final base64Audio = responseData['audioContent'];

        if (base64Audio != null && base64Audio.isNotEmpty) {
          final Uint8List rawPcm = base64Decode(base64Audio);
          // 💡 回傳前，套上 WAV 檔頭，這樣儲存下來的檔案才會有乾淨、沒有雜音的聲音！
          return _addWavHeader(rawPcm);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

// =========================================================================
// 🎙️ 6. 雅婷全端語音服務整合版
// =========================================================================
class YatingSpeechService implements ISTTService, ITTSService {
  final YatingSttService _sttService = YatingSttService();
  final YatingTtsService _ttsService = YatingTtsService();
  @override
  Future<String?> transcribe(String audioFilePath) =>
      _sttService.transcribe(audioFilePath);
  @override
  Future<Uint8List?> generateSpeech(String text, String language) =>
      _ttsService.generateSpeech(text, language);
}
