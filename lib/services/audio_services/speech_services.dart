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
import 'taiwanese_tts_fallback.dart';
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
  NckuSpeechService({
    TaiLoConverter? taiLoConverter,
    LegacyTaiwaneseTts? legacyTaiwanese,
    TaiwaneseTtsFallback? taiwaneseFallback,
    String? ttsHost,
    int? ttsPort,
    bool? ttsTls,
    String Function()? ttsToken,
    Duration totalTtsBudget = defaultTotalTtsBudget,
  }) : _taiLo = taiLoConverter,
       _fallback =
           taiwaneseFallback ??
           TaiwaneseTtsFallback.parse(
             ReminiCareConfig.getValue(TaiwaneseTtsFallback.configKey),
           ),
       _ttsHost =
           ttsHost ??
           (ReminiCareConfig.getValue('NCKU_TTS_HOST').isEmpty
               ? '140.116.245.146'
               : ReminiCareConfig.getValue('NCKU_TTS_HOST')),
       _ttsPort =
           ttsPort ??
           int.tryParse(ReminiCareConfig.getValue('NCKU_TTS_PORT')) ??
           9998,
       _ttsTls = ttsTls ?? ReminiCareConfig.getValue('NCKU_TTS_TLS') == 'true',
       _ttsToken = ttsToken ?? (() => ReminiCareConfig.nckuTtsToken),
       _totalTtsBudget = totalTtsBudget,
       _legacyOverride = legacyTaiwanese;

  /// 台語備援最多依序打三個服務；總時限需小於 TtsCache 的外層逾時。
  static const defaultTotalTtsBudget = Duration(seconds: 140);

  /// 9998 拒絕漢字後，這段時間內台語漢字直接走備援，不再白打一次。
  static const hanziRejectionMemory = Duration(minutes: 10);

  final TaiLoConverter? _taiLo;
  final TaiwaneseTtsFallback _fallback;
  final String _ttsHost;
  final int _ttsPort;
  final bool _ttsTls;
  final String Function() _ttsToken;
  final Duration _totalTtsBudget;
  final LegacyTaiwaneseTts? _legacyOverride;
  late final LegacyTaiwaneseTts _legacy =
      _legacyOverride ?? NckuLegacyTaiwaneseTts(token: _ttsToken);
  final String _ttsEndOfTransmission = 'EOT';
  final String _ttsApiId = '10012';
  DateTime? _hanziRejectedAt;

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
    if (text.isEmpty || text.contains('@@@')) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        detail: 'invalidInput',
      );
      return null;
    }
    final clock = Stopwatch()..start();
    Duration remaining() => _totalTtsBudget - clock.elapsed;

    if (language != '台語') {
      return (await _synthesizeVits(text, 'zh', '4793', remaining())).audio;
    }

    // 1. 9998 直接送原文；伺服器修好後這一步就會成功。
    final hasHan = containsHan(text);
    final rejectedAt = _hanziRejectedAt;
    final skipDirect =
        hasHan &&
        _fallback != TaiwaneseTtsFallback.off &&
        rejectedAt != null &&
        DateTime.now().difference(rejectedAt) < hanziRejectionMemory;
    var vitsReachable = true;
    if (!skipDirect) {
      final direct = await _synthesizeVits(text, 'tw', 'M04', remaining());
      if (direct.audio != null) {
        if (hasHan) _hanziRejectedAt = null;
        return direct.audio;
      }
      if (direct.rejected && hasHan) _hanziRejectedAt = DateTime.now();
      vitsReachable = direct.rejected;
    }
    if (_fallback == TaiwaneseTtsFallback.off) return null;

    // 2. LLM 轉台羅後再送 9998；9998 連不上時這一步沒有意義。
    final converter = _taiLo;
    if (_fallback.usesLlm && hasHan && vitsReachable && converter != null) {
      final tailo = await _convertToTaiLo(converter, text, remaining());
      if (tailo != null && remaining() > Duration.zero) {
        final retry = await _synthesizeVits(
          tailo,
          'tw',
          'M04',
          remaining(),
          startDetail: 'tailo',
        );
        if (retry.audio != null) return retry.audio;
      }
    }

    // 3. 舊版 10012 伺服器：接受漢字，但音質與正確度較差。
    if (_fallback.usesLegacy && remaining() > Duration.zero) {
      return _synthesizeLegacy(text, remaining());
    }
    return null;
  }

  Future<String?> _convertToTaiLo(
    TaiLoConverter converter,
    String text,
    Duration timeout,
  ) async {
    if (timeout <= Duration.zero) return null;
    final watch = Stopwatch()..start();
    AppLog.instance.record(LogArea.tts, LogEvent.warning, detail: 'tailo');
    try {
      final tailo = await converter.toTaiLo(text, timeout: timeout);
      if (tailo == null) {
        AppLog.instance.record(
          LogArea.tts,
          LogEvent.failed,
          durationMs: watch.elapsedMilliseconds,
          detail: 'invalidResponse',
        );
      }
      return tailo;
    } catch (e) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        durationMs: watch.elapsedMilliseconds,
        detail: e is TimeoutException ? 'timeout' : 'invalidResponse',
      );
      return null;
    }
  }

  Future<Uint8List?> _synthesizeLegacy(String text, Duration timeout) async {
    final watch = Stopwatch()..start();
    AppLog.instance.record(
      LogArea.tts,
      LogEvent.warning,
      detail: 'legacyServer',
    );
    try {
      final audio = await _legacy.synthesize(text, timeout: timeout);
      AppLog.instance.record(
        LogArea.tts,
        audio == null ? LogEvent.failed : LogEvent.completed,
        bytes: audio?.length,
        durationMs: watch.elapsedMilliseconds,
        detail: audio == null ? 'invalidResponse' : 'legacyServer',
      );
      return audio;
    } catch (e) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        durationMs: watch.elapsedMilliseconds,
        detail: e is TimeoutException ? 'timeout' : 'network',
      );
      return null;
    }
  }

  Future<_VitsOutcome> _synthesizeVits(
    String text,
    String langCode,
    String speaker,
    Duration timeout, {
    String? startDetail,
  }) async {
    final watch = Stopwatch()..start();
    AppLog.instance.record(
      LogArea.tts,
      LogEvent.started,
      detail: startDetail ?? langCode,
    );
    if (timeout <= Duration.zero) {
      AppLog.instance.record(LogArea.tts, LogEvent.failed, detail: 'timeout');
      return const _VitsOutcome();
    }

    Socket? socket;
    try {
      final connector = _ttsTls ? SecureSocket.connect : Socket.connect;
      socket = await connector(
        _ttsHost,
        _ttsPort,
        timeout: const Duration(seconds: 5),
      );
      final String message =
          "$_ttsApiId@@@${_ttsToken()}@@@$langCode@@@$speaker@@@$text$_ttsEndOfTransmission";

      socket.add(utf8.encode(message));
      await socket.flush();

      final List<int> responseBytes = [];
      await socket
          .forEach(responseBytes.addAll)
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException('成大 TTS 伺服器接收超時'),
          );

      final String resultString = utf8.decode(responseBytes);
      if (resultString.isEmpty) {
        AppLog.instance.record(
          LogArea.tts,
          LogEvent.failed,
          durationMs: watch.elapsedMilliseconds,
          detail: 'invalidResponse',
        );
        return const _VitsOutcome();
      }
      final Map<String, dynamic> response =
          jsonDecode(resultString) as Map<String, dynamic>;

      if (response["status"] == true) {
        final Uint8List wavBytes = base64Decode(response["bytes"] ?? "");
        if (wavBytes.isEmpty) {
          AppLog.instance.record(
            LogArea.tts,
            LogEvent.failed,
            durationMs: watch.elapsedMilliseconds,
            detail: 'invalidResponse',
          );
          return const _VitsOutcome();
        }
        AppLog.instance.record(
          LogArea.tts,
          LogEvent.completed,
          bytes: wavBytes.length,
          durationMs: watch.elapsedMilliseconds,
          detail: startDetail ?? langCode,
        );
        return _VitsOutcome(audio: wavBytes);
      }
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        durationMs: watch.elapsedMilliseconds,
        detail: 'server',
      );
      return const _VitsOutcome(rejected: true);
    } catch (e) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.failed,
        durationMs: watch.elapsedMilliseconds,
        detail: e is TimeoutException
            ? 'timeout'
            : e is FormatException
            ? 'invalidResponse'
            : 'network',
      );
      return const _VitsOutcome();
    } finally {
      socket?.destroy();
    }
  }
}

class _VitsOutcome {
  const _VitsOutcome({this.audio, this.rejected = false});
  final Uint8List? audio;

  /// 伺服器有回應但拒絕合成（status=false），代表 9998 本身可連線。
  final bool rejected;
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
              if (pipe['asr_eof'] == true && !finished.isCompleted) {
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
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.requestFailed,
        statusCode: response.statusCode,
        bytes: response.bodyBytes.length,
        detail: switch (response.statusCode) {
          401 || 403 => 'authentication',
          402 => 'billing',
          429 => 'rateLimit',
          >= 500 => 'server',
          _ => 'invalidResponse',
        },
      );
      return null;
    } on TimeoutException {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.requestFailed,
        detail: 'timeout',
      );
      return null;
    } catch (e) {
      AppLog.instance.record(
        LogArea.tts,
        LogEvent.requestFailed,
        detail: 'network',
      );
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
