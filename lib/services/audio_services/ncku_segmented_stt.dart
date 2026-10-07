import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'stt_result.dart';
import 'wav_audio.dart';
import 'speech_recognition_job.dart';

class _Segment {
  _Segment(this.audio);
  final WavAudio audio;
  String? text;
  List<_Segment>? children;
}

class NckuSegmentedStt implements ProgressSttService, JobSttService {
  NckuSegmentedStt({
    http.Client? client,
    required this.token,
    this.timeout = const Duration(seconds: 60),
    Uri? endpoint,
    http.Client Function()? clientFactory,
  }) : _client = client ?? http.Client(),
       _endpoint = endpoint,
       _clientFactory = clientFactory ?? http.Client.new;
  final http.Client _client;
  final String Function() token;
  final Duration timeout;
  Uri get endpoint =>
      _endpoint ?? Uri.parse('http://140.116.245.149:5002/proxy');
  Uri? _endpoint;
  final http.Client Function() _clientFactory;
  final _jobs = <String, List<_Segment>>{};
  final _cancelledPaths = <String>{};
  final _activeWorkers = <String, NckuSegmentedStt>{};
  bool _cancelled = false;
  @override
  SpeechRecognitionJob createJob(String path) => SpeechRecognitionJob(
    run: (progress) async {
      _cancelledPaths.remove(path);
      final worker = NckuSegmentedStt(
        token: token,
        timeout: timeout,
        client: _clientFactory(),
      );
      worker._endpoint = endpoint;
      worker.onProgress = progress;
      if (_jobs.containsKey(path)) worker._jobs[path] = _jobs[path]!;
      _activeWorkers[path] = worker;
      try {
        final text = await worker.transcribe(path);
        return SttResult(text: text ?? '');
      } on SttException catch (error) {
        return SttResult(error: error);
      } finally {
        if (!worker._cancelled &&
            !_cancelledPaths.contains(path) &&
            worker._jobs.containsKey(path)) {
          _jobs[path] = worker._jobs[path]!;
        }
        worker._client.close();
        if (identical(_activeWorkers[path], worker)) {
          _activeWorkers.remove(path);
        }
        _cancelledPaths.remove(path);
      }
    },
    abort: () {
      _cancelledPaths.add(path);
      final worker = _activeWorkers.remove(path);
      worker?._cancelled = true;
      worker?._client.close();
    },
  );
  @override
  void Function(int complete, int total)? onProgress;
  @override
  void forget(String path) {
    _cancelledPaths.add(path);
    final worker = _activeWorkers.remove(path);
    worker?._cancelled = true;
    worker?._client.close();
    if (worker == null) _cancelledPaths.remove(path);
    _jobs.remove(path);
  }

  static const maximumBodyBytes = 240 * 1024;

  String bodyFor(WavAudio audio) =>
      {
            'lang': 'Chinese & Taiwanese',
            'token': token(),
            'audio': base64Encode(audio.encode()),
          }.entries
          .map(
            (entry) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
          )
          .join('&');

  Future<String?> transcribe(String path) async {
    _cancelledPaths.remove(path);
    final progress = onProgress;
    try {
      if (token().isEmpty) {
        throw const SttException(
          SttErrorKind.authentication,
          '請設定成大 STT Token。',
        );
      }
      if (!_jobs.containsKey(path)) {
        final audio = WavAudio.parse(await File(path).readAsBytes());
        _jobs[path] = audio.split().map(_Segment.new).toList();
        debugPrint(
          '[NCKU STT] ${audio.seconds.toStringAsFixed(1)} 秒，${audio.pcm.length} bytes，${_jobs[path]!.length} 段',
        );
      }
      final segments = _jobs[path]!;
      var next = 0;
      SttException? failure;
      var complete = segments.where((s) => s.text != null).length;
      progress?.call(complete, segments.length);
      Future<void> worker() async {
        while (next < segments.length) {
          if (_cancelled || _cancelledPaths.contains(path)) {
            throw const SttException(SttErrorKind.cancelled, '已取消辨識。');
          }
          final segment = segments[next++];
          if (segment.text != null) continue;
          try {
            segment.text = await _recognize(segment);
            progress?.call(++complete, segments.length);
          } on SttException catch (error) {
            failure ??= error;
          }
        }
      }

      await Future.wait([worker(), worker()]);
      if (failure != null) throw failure!;
      final text = segments
          .map((s) => s.text ?? '')
          .where((s) => s.isNotEmpty)
          .join('，');
      return text.isEmpty ? null : text;
    } on SttException {
      rethrow;
    } on FormatException catch (error) {
      debugPrint('[NCKU STT] 音檔驗證失敗：${error.message}');
      throw const SttException(SttErrorKind.invalidAudio, '錄音格式不正確或音檔不完整。');
    } catch (_) {
      throw const SttException(SttErrorKind.network, '無法讀取或傳送錄音，請重試。');
    }
  }

  Future<String> _recognize(_Segment segment) async {
    if (_cancelled) throw const SttException(SttErrorKind.cancelled, '已取消辨識。');
    if (segment.text != null) return segment.text!;
    if (segment.children != null) {
      final texts = <String>[];
      for (final child in segment.children!) {
        texts.add(await _recognize(child));
      }
      return segment.text = texts.where((s) => s.isNotEmpty).join('，');
    }
    final body = bodyFor(segment.audio);
    if (utf8.encode(body).length > maximumBodyBytes) return _subdivide(segment);
    final watch = Stopwatch()..start();
    try {
      final response = await _client
          .post(
            endpoint,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(timeout);
      debugPrint(
        '[NCKU STT] 請求 ${utf8.encode(body).length} bytes，HTTP ${response.statusCode}，${watch.elapsedMilliseconds} ms',
      );
      if (response.statusCode == 413 ||
          (response.statusCode >= 400 &&
              RegExp(
                r'413|Request Entity Too Large',
                caseSensitive: false,
              ).hasMatch(response.body))) {
        return _subdivide(segment);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const SttException(
          SttErrorKind.authentication,
          '成大 STT Token 無效。',
        );
      }
      if (response.statusCode != 200) {
        throw const SttException(SttErrorKind.server, '成大語音辨識服務暫時失敗，請重試。');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['sentence'] is! String) {
        throw const SttException(
          SttErrorKind.invalidResponse,
          '成大 STT 回傳格式不正確。',
        );
      }
      final text = (decoded['sentence'] as String).trim();
      return segment.text = text == '<{silent}>' ? '' : text;
    } on TimeoutException {
      throw const SttException(SttErrorKind.timeout, '語音辨識逾時，請重試。');
    } on SttException {
      rethrow;
    } on FormatException {
      throw const SttException(SttErrorKind.invalidResponse, '成大 STT 回傳格式不正確。');
    } catch (_) {
      throw const SttException(SttErrorKind.network, '語音辨識連線失敗，請重試。');
    }
  }

  Future<String> _subdivide(_Segment segment) async {
    if (segment.audio.pcm.length < 2 * WavAudio.bytesPerSecond) {
      throw const SttException(
        SttErrorKind.payloadTooLarge,
        '成大 STT 仍拒絕短錄音，請稍後重試或切換語音服務。',
      );
    }
    final middle = (segment.audio.pcm.length ~/ 4) * 2;
    segment.children = [
      _Segment(WavAudio(segment.audio.pcm.sublist(0, middle))),
      _Segment(WavAudio(segment.audio.pcm.sublist(middle))),
    ];
    return _recognize(segment);
  }
}
