import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:remini_care_ai_app/services/remini_care_config.dart';

// =========================================================================
// 💡 1. 定義通用的語音辨識 (STT) 介面
// =========================================================================
abstract class ISTTService {
  /// 傳入本機音檔路徑，回傳辨識後的文字
  Future<String?> transcribe(String audioFilePath);
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
class NckuSpeechService implements ISTTService, ITTSService {
  final String _ttsHost = '140.116.245.146';
  final int _ttsPort = 9998;
  final String _ttsEndOfTransmission = 'EOT';
  final String _ttsApiId = '10012';
  final String _sttUrl = 'http://140.116.245.149:5002/proxy';

  /// 一、成大自研語音辨識服務 (STT)
  @override
  Future<String?> transcribe(String audioFilePath) async {
    if (kIsWeb) {
      debugPrint("[NCKU STT] 瀏覽器 Web 安全限制不支援直接檔案讀取。");
      return null;
    }
    try {
      debugPrint("[NCKU STT] 讀取音檔: $audioFilePath");
      final file = File(audioFilePath);
      if (!await file.exists()) {
        debugPrint("[NCKU STT] ❌ 音檔不存在");
        return null;
      }

      final List<int> fileBytes = await file.readAsBytes();
      debugPrint("[NCKU STT] 音檔大小: ${fileBytes.length} bytes");

      final String base64Audio = base64Encode(fileBytes);

      final Map<String, String> data = {
        "lang": "Chinese & Taiwanese",
        "token": ReminiCareConfig.nckuSttToken,
        "audio": base64Audio,
      };

      debugPrint("[NCKU STT] POST → $_sttUrl");
      final response = await http
          .post(Uri.parse(_sttUrl), body: data)
          .timeout(const Duration(seconds: 60));

      debugPrint("[NCKU STT] 回應 status=${response.statusCode}");

      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final String? sentence = body["sentence"] as String?;

        if (sentence == null || sentence == "<{silent}>") {
          debugPrint("[NCKU STT] 偵測為靜音");
          return null;
        }

        final String trimmedSentence = sentence.trim();
        debugPrint("[NCKU STT] 辨識成功: '$trimmedSentence'");
        return trimmedSentence;
      } else {
        debugPrint("[NCKU STT] ❌ 請求失敗: ${response.statusCode} body=${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("[NCKU STT] ❌ ASR 連線與解析出錯: $e");
      return null;
    }
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
      final Socket socket = await Socket.connect(_ttsHost, _ttsPort, timeout: const Duration(seconds: 5));
      final String message = "$_ttsApiId@@@$token@@@$langCode@@@$speaker@@@$text$_ttsEndOfTransmission";

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

            final Map<String, dynamic> response = jsonDecode(resultString) as Map<String, dynamic>;

            if (response["status"] == true) {
              final String base64Wav = response["bytes"] ?? "";
              final Uint8List wavBytes = base64Decode(base64Wav);

              debugPrint("✅ [NCKU TTS 成功] 語音合成流加載完成。");
              completer.complete(wavBytes);
            } else {
              final String error = response["message"] ?? response["Message"] ?? "Unknown Error";
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

  Uint8List _extractPcmFromWav(Uint8List bytes) {
    if (bytes.length < 12) return bytes;
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') return bytes.length > 44 ? bytes.sublist(44) : bytes;

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = ByteData.sublistView(bytes, offset + 4, offset + 8).getUint32(0, Endian.little);
      if (chunkId == 'data') {
        int end = offset + 8 + chunkSize;
        if (end > bytes.length) end = bytes.length;
        return bytes.sublist(offset + 8, end);
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 != 0) offset += 1;
    }
    return bytes.length > 44 ? bytes.sublist(44) : bytes;
  }

  @override
  Future<String?> transcribe(String audioFilePath) async {
    if (kIsWeb) return null;

    debugPrint("\n========== [Yating STT Debug 開始] ==========");
    debugPrint("[Yating STT Debug] 📁 準備處理音檔: $audioFilePath");

    try {
      final file = File(audioFilePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.length <= 44) {
        debugPrint("[Yating STT Debug] ❌ 致命錯誤：音檔過小，代表麥克風錄製到空音軌。");
        return null;
      }

      final pcmBytes = _extractPcmFromWav(bytes);
      if (pcmBytes.isEmpty) return null;

      final tokenResponse = await http.post(
        Uri.parse(_tokenUrl),
        headers: { 'key': ReminiCareConfig.yatingApiKey, 'Content-Type': 'application/json' },
        body: jsonEncode({ "pipeline": "asr-zh-tw-std" }),
      ).timeout(const Duration(seconds: 10));

      if (tokenResponse.statusCode != 201) return null;
      final tokenData = jsonDecode(tokenResponse.body);
      if (tokenData['success'] != true || tokenData['auth_token'] == null) return null;

      final ws = await WebSocket.connect('$_wsBaseUrl?token=${tokenData['auth_token']}');
      final completer = Completer<String?>();

      String fullTranscript = "";
      String currentSentence = "";
      bool isReadyToSend = false;

      ws.listen(
            (message) async {
          if (message is String) {
            final data = jsonDecode(message);
            if (data['status'] == 'error') {
              if (!completer.isCompleted) completer.complete(fullTranscript + currentSentence);
              ws.close();
              return;
            }

            if (data['status'] == 'ok') isReadyToSend = true;

            if (data['pipe'] != null) {
              final pipe = data['pipe'];
              if (pipe['asr_sentence'] != null) currentSentence = pipe['asr_sentence'];

              if (pipe['asr_final'] == true) {
                fullTranscript += currentSentence + "，";
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
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(fullTranscript + currentSentence);
        },
      );

      int waitReadyCount = 0;
      while (!isReadyToSend && waitReadyCount < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitReadyCount++;
      }

      if (!isReadyToSend) {
        ws.close();
        return null;
      }

      final int chunkSize = 2000;
      for (int i = 0; i < pcmBytes.length; i += chunkSize) {
        if (ws.readyState != WebSocket.open) break;
        int end = (i + chunkSize < pcmBytes.length) ? i + chunkSize : pcmBytes.length;
        ws.add(pcmBytes.sublist(i, end));
        await Future.delayed(const Duration(milliseconds: 20));
      }

      if (ws.readyState == WebSocket.open) {
        ws.add(Uint8List(0));
      }

      Timer eofFallbackTimer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) {
          debugPrint("[Yating STT Debug] ⏱️ 伺服器已讀取完畢但未回傳 asr_eof (靜音裝死)，強制結算！");
          completer.complete(fullTranscript + currentSentence);
          ws.close();
        }
      });

      final String? finalTranscription = await completer.future;
      eofFallbackTimer.cancel();

      String cleanedTranscription = finalTranscription?.replaceAll(RegExp(r'^[，\s]+|[，\s]+$'), '') ?? "";
      debugPrint("[Yating STT Debug] ✅ 最終辨識結果: ${cleanedTranscription.isEmpty ? '(空)' : cleanedTranscription}");
      debugPrint("========== [Yating STT Debug 結束] ==========\n");

      return cleanedTranscription.isNotEmpty ? cleanedTranscription.trim() : null;

    } catch (e) {
      return null;
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
    header.setUint8(0, 82); header.setUint8(1, 73); header.setUint8(2, 70); header.setUint8(3, 70);
    header.setUint32(4, 36 + pcmData.length, Endian.little);

    // 'WAVE' format
    header.setUint8(8, 87); header.setUint8(9, 65); header.setUint8(10, 86); header.setUint8(11, 69);

    // 'fmt ' subchunk
    header.setUint8(12, 102); header.setUint8(13, 109); header.setUint8(14, 116); header.setUint8(15, 32);
    header.setUint32(16, 16, Endian.little); // PCM size
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little); // BlockAlign
    header.setUint16(34, 16, Endian.little); // BitsPerSample

    // 'data' subchunk
    header.setUint8(36, 100); header.setUint8(37, 97); header.setUint8(38, 116); header.setUint8(39, 97);
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
        "input": { "text": text, "type": "text" },
        "voice": { "model": model, "speed": 1.0, "pitch": 1.0, "energy": 1.0 },
        // 我們要求 16K 的 Raw PCM 數據
        "audioConfig": { "encoding": "LINEAR16", "sampleRate": "16K" }
      };

      final response = await http.post(
        Uri.parse(_ttsUrl),
        headers: { 'Content-Type': 'application/json', 'key': ReminiCareConfig.yatingApiKey },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

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
  Future<String?> transcribe(String audioFilePath) => _sttService.transcribe(audioFilePath);
  @override
  Future<Uint8List?> generateSpeech(String text, String language) => _ttsService.generateSpeech(text, language);
}