import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:remini_care_ai_app/services/remini_care_config.dart';


// =========================================================================
// 💡 4. 成大自研語音與音訊整合服務 (100% 完美接合 NCKU ASR & VITS TCP-TTS 原始架構)
// =========================================================================
class NckuSpeechService {
  final String _ttsHost = '140.116.245.146';
  final int _ttsPort = 9998;
  final String _ttsEndOfTransmission = 'EOT';
  final String _ttsApiId = '10012';
  final String _sttUrl = 'http://140.116.245.149:5002/proxy';

  /// 一、成大自研語音辨識服務 (100% 同步 ASR Form-Encoded 規格)
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

  /// 二、成大自研語音合成服務 (100% 同步 Port 9998 VITS-TCP 協定)
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