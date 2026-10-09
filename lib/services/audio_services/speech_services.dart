import '../app_log.dart';
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
import 'speech_recognition_job.dart';

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
    implements ISTTService, ITTSService, ProgressSttService, JobSttService {
  final _segmented = NckuSegmentedStt(
    token: () => ReminiCareConfig.nckuSttToken,
    endpoint: Uri.parse(
      ReminiCareConfig.getValue('NCKU_STT_URL').isEmpty
          ? 'http://140.116.245.149:5002/proxy'
          : ReminiCareConfig.getValue('NCKU_STT_URL'),
    ),
  );
  @override
  SpeechRecognitionJob createJob(String path) => _segmented.createJob(path);
  @override
  void Function(int, int)? get onProgress => _segmented.onProgress;
  @override
  set onProgress(void Function(int, int)? value) =>
      _segmented.onProgress = value;
  @override
  void forget(String path) => _segmented.forget(path);
  final String _ttsHost = ReminiCareConfig.getValue('NCKU_TTS_HOST').isEmpty
      ? '140.116.245.146'
      : ReminiCareConfig.getValue('NCKU_TTS_HOST');
  final int _ttsPort =
      int.tryParse(ReminiCareConfig.getValue('NCKU_TTS_PORT')) ?? 9998;
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
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        detail: 'unsupportedCapability',
      );
      return null;
    }
    if (text.isEmpty) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        detail: 'invalidInput',
      );
      return null;
    }
    if (text.contains('@@@')) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        detail: 'invalidInput',
      );
      return null;
    }

    final String langCode = (language == "台語") ? "tw" : "zh";
    final String speaker = (language == "台語") ? "M04" : "4793";
    final String token = ReminiCareConfig.nckuTtsToken;

    final watch = Stopwatch()..start();
    AppLog.instance.record(LogArea.tts, LogEvent.started, detail: langCode);

    Socket? socket;
    try {
      final connector = ReminiCareConfig.getValue('NCKU_TTS_TLS') == 'true'
          ? SecureSocket.connect
          : Socket.connect;
      socket = await connector(
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
              if (!completer.isCompleted) completer.complete(null);
              return;
            }

            final Map<String, dynamic> response =
                jsonDecode(resultString) as Map<String, dynamic>;

            if (response["status"] == true) {
              final String base64Wav = response["bytes"] ?? "";
              final Uint8List wavBytes = base64Decode(base64Wav);

              AppLog.instance.record(
                LogArea.tts,
                LogEvent.completed,
                bytes: wavBytes.length,
                durationMs: watch.elapsedMilliseconds,
                detail: langCode,
              );
              if (!completer.isCompleted) completer.complete(wavBytes);
            } else {
              AppLog.instance.record(
                LogArea.tts,
                LogEvent.failed,
                durationMs: watch.elapsedMilliseconds,
                detail: 'server',
              );
              if (!completer.isCompleted) completer.complete(null);
            }
          } catch (e) {
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      final Uint8List? audioData = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('成大 TTS 伺服器接收超時'),
      );

      return audioData;
    } catch (e) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        durationMs: watch.elapsedMilliseconds,
        detail: e is TimeoutException ? 'timeout' : 'network',
      );
      return null;
    } finally {
      socket?.destroy();
    }
  }
}

// =========================================================================
// 🎙️ 4. 雅婷即時語音服務 (Yating Real-time ASR) 實作 STT
// =========================================================================
abstract interface class YatingChannel {
  Stream<dynamic> get messages;
  void send(dynamic data);
  Future<void> close();
}

class NativeYatingChannel implements YatingChannel {
  NativeYatingChannel(this.socket);
  final WebSocket socket;
  @override
  Stream<dynamic> get messages => socket;
  @override
  void send(dynamic data) => socket.add(data);
  @override
  Future<void> close() async {
    await socket.close();
  }
}

class YatingSttService implements ISTTService, JobSttService {
  YatingSttService({
    http.Client? client,
    this.connect,
    this.completionTimeout = const Duration(seconds: 30),
    this.sendDelay = const Duration(microseconds: 62500),
  }) : _http = client ?? http.Client();
  final http.Client _http;
  final Future<YatingChannel> Function(String)? connect;
  final Duration completionTimeout;
  final Duration sendDelay;
  final _cancelled = Completer<void>();
  YatingChannel? _channel;
  bool _running = false;

  @override
  SpeechRecognitionJob createJob(String path) {
    final worker = YatingSttService(
      connect: connect,
      completionTimeout: completionTimeout,
      sendDelay: sendDelay,
    );
    return SpeechRecognitionJob(
      run: (progress) async {
        progress(0, 1);
        try {
          final text = await worker.transcribe(path);
          progress(1, 1);
          return SttResult(text: text ?? '');
        } on SttException catch (error) {
          return SttResult(error: error);
        } finally {
          worker._http.close();
        }
      },
      abort: worker.cancel,
    );
  }

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    _http.close();
    unawaited(_channel?.close() ?? Future<void>.value());
  }

  Future<T> _wait<T>(Future<T> value) => Future.any([
    value,
    _cancelled.future.then<T>(
      (_) => throw const SttException(SttErrorKind.cancelled, '已取消辨識。'),
    ),
  ]);

  @override
  Future<String?> transcribe(String path) async {
    if (_running) throw const SttException(SttErrorKind.server, '辨識工作已在執行。');
    _running = true;
    StreamSubscription<dynamic>? subscription;
    final finished = Completer<String>();
    final ready = Completer<void>();
    finished.future.ignore();
    ready.future.ignore();
    var full = '';
    var current = '';
    String partial() => (full + current).trim();
    void fail(SttException error) {
      if (!ready.isCompleted) ready.completeError(error);
      if (!finished.isCompleted) finished.completeError(error);
    }

    try {
      final audio = WavAudio.parse(await File(path).readAsBytes());
      final response = await _wait(
        _http
            .post(
              Uri.parse('https://asr.api.yating.tw/v1/token'),
              headers: {
                'key': ReminiCareConfig.yatingApiKey,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'pipeline': 'asr-zh-tw-std'}),
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (response.statusCode != 201) {
        throw const SttException(SttErrorKind.authentication, '雅婷 STT 驗證失敗。');
      }
      final token = jsonDecode(utf8.decode(response.bodyBytes));
      if (token is! Map ||
          token['success'] != true ||
          token['auth_token'] is! String) {
        throw const SttException(
          SttErrorKind.invalidResponse,
          '雅婷 STT 驗證回應不正確。',
        );
      }
      final connection = connect != null
          ? connect!(
              'wss://asr.api.yating.tw/ws/v1/?token=${token['auth_token']}',
            )
          : WebSocket.connect(
              'wss://asr.api.yating.tw/ws/v1/?token=${token['auth_token']}',
            ).then<YatingChannel>(NativeYatingChannel.new);
      var abandoned = false;
      connection.then((channel) {
        if (abandoned || _cancelled.isCompleted) unawaited(channel.close());
      }, onError: (Object _) {});
      try {
        _channel = await _wait(connection.timeout(const Duration(seconds: 10)));
      } catch (_) {
        abandoned = true;
        rethrow;
      }
      subscription = _channel!.messages.listen(
        (message) {
          try {
            if (message is! String) return;
            final data = jsonDecode(message);
            if (data is! Map) throw const FormatException('Invalid ASR event');
            if (data['status'] == 'error') {
              fail(const SttException(SttErrorKind.server, '雅婷辨識服務回報錯誤。'));
              return;
            }
            if (data['status'] == 'ok' && !ready.isCompleted) ready.complete();
            final pipe = data['pipe'];
            if (pipe is Map) {
              if (pipe['asr_sentence'] is String) {
                current = pipe['asr_sentence'];
              }
              if (pipe['asr_final'] == true) {
                full += '$current，';
                current = '';
              }
              if (pipe['asr_state'] == 'asr_eof' && !finished.isCompleted) {
                finished.complete(partial());
              }
            }
          } catch (_) {
            fail(
              const SttException(SttErrorKind.invalidResponse, '雅婷回傳格式不正確。'),
            );
          }
        },
        onError: (Object _) {
          fail(
            SttException(
              SttErrorKind.network,
              '雅婷辨識連線失敗。',
              partialText: partial(),
            ),
          );
        },
        onDone: () {
          if (!finished.isCompleted) {
            fail(
              SttException(
                SttErrorKind.incomplete,
                '辨識連線未完整結束，請重試。',
                partialText: partial(),
              ),
            );
          }
        },
      );
      await _wait(ready.future.timeout(const Duration(seconds: 5)));
      for (var offset = 0; offset < audio.pcm.length; offset += 2000) {
        if (finished.isCompleted) break;
        if (_cancelled.isCompleted) {
          throw const SttException(SttErrorKind.cancelled, '已取消辨識。');
        }
        _channel!.send(
          audio.pcm.sublist(offset, (offset + 2000).clamp(0, audio.pcm.length)),
        );
        await _wait(Future<void>.delayed(sendDelay));
      }
      _channel!.send(Uint8List(0));
      final text = await _wait(
        finished.future.timeout(
          completionTimeout,
          onTimeout: () => throw SttException(
            SttErrorKind.incomplete,
            '辨識尚未完整完成，請重試。',
            partialText: partial(),
          ),
        ),
      );
      return text.replaceAll(RegExp(r'^[，\s]+|[，\s]+$'), '');
    } on SttException {
      rethrow;
    } on TimeoutException {
      throw SttException(
        SttErrorKind.timeout,
        '雅婷語音辨識逾時。',
        partialText: partial(),
      );
    } on FormatException {
      throw const SttException(SttErrorKind.invalidAudio, '錄音或辨識回應格式不正確。');
    } catch (_) {
      throw SttException(
        SttErrorKind.network,
        '雅婷語音辨識失敗，請重試。',
        partialText: partial(),
      );
    } finally {
      await subscription?.cancel();
      await _channel?.close();
      _running = false;
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
class YatingSpeechService implements ISTTService, ITTSService, JobSttService {
  final YatingSttService _sttService = YatingSttService();
  final YatingTtsService _ttsService = YatingTtsService();
  @override
  SpeechRecognitionJob createJob(String path) => _sttService.createJob(path);
  @override
  Future<String?> transcribe(String audioFilePath) =>
      _sttService.transcribe(audioFilePath);
  @override
  Future<Uint8List?> generateSpeech(String text, String language) =>
      _ttsService.generateSpeech(text, language);
}
