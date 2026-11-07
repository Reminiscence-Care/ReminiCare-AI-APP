import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

enum LogArea {
  app,
  flow,
  recording,
  stt,
  tts,
  ai,
  llm,
  image,
  settings,
  history,
  cache,
}

enum LogEvent {
  started,
  completed,
  failed,
  cancelled,
  progress,
  stageChanged,
  warning,
  recordingStopped,
  requestStarted,
  requestCompleted,
  requestFailed,
  cacheHit,
  saving,
  saved,
  cleared,
  frameworkError,
  transcription,
  partialTranscription,
}

class AppLogEntry {
  const AppLogEntry({
    required this.id,
    required this.time,
    required this.elapsed,
    required this.area,
    required this.event,
    this.operationId,
    this.durationMs,
    this.bytes,
    this.complete,
    this.total,
    this.statusCode,
    this.detail,
    this.transcript,
    this.transcriptTruncated = false,
  });
  final int id;
  final DateTime time;
  final Duration elapsed;
  final LogArea area;
  final LogEvent event;
  final int? operationId, durationMs, bytes, complete, total, statusCode;
  final String? detail;
  final String? transcript;
  final bool transcriptTruncated;
  bool get isError =>
      event == LogEvent.failed ||
      event == LogEvent.requestFailed ||
      event == LogEvent.frameworkError ||
      (statusCode != null && statusCode! >= 400);
  String get message {
    final label = switch (event) {
      LogEvent.started => '開始',
      LogEvent.completed => '完成',
      LogEvent.failed => '失敗',
      LogEvent.cancelled => '取消',
      LogEvent.progress => '進度',
      LogEvent.stageChanged => '切換階段',
      LogEvent.warning => '警告',
      LogEvent.recordingStopped => '錄音停止',
      LogEvent.requestStarted => '送出請求',
      LogEvent.requestCompleted => '收到回應',
      LogEvent.requestFailed => '請求失敗',
      LogEvent.cacheHit => '使用快取',
      LogEvent.saving => '開始保存',
      LogEvent.saved => '保存完成',
      LogEvent.cleared => '清理完成',
      LogEvent.frameworkError => '介面錯誤',
      LogEvent.transcription => '辨識結果',
      LogEvent.partialTranscription => '部分辨識結果（未完整成功）',
    };
    return '$label${detail == null ? '' : '・${AppLog.detailLabels[detail] ?? detail}'}';
  }

  String get line {
    String pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    final stamp =
        '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}.${pad(time.millisecond, 3)}';
    final seconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(3);
    final metrics = [
      if (operationId != null) '操作=$operationId',
      if (durationMs != null) '耗時=$durationMs ms',
      if (bytes != null) '大小=$bytes bytes',
      if (complete != null && total != null) '進度=$complete/$total',
      if (statusCode != null) 'HTTP=$statusCode',
      if (transcript != null) '文字=${jsonEncode(transcript)}',
      if (transcriptTruncated) '文字已截短',
    ];
    return '$stamp (+$seconds 秒) [${area.name.toUpperCase()}] $message${metrics.isEmpty ? '' : '  ${metrics.join('  ')}'}';
  }
}

/// In-memory diagnostics. Free-form messages, URLs, payloads and exceptions are
/// deliberately not accepted. STT text has a dedicated bounded recording method.
class AppLog extends ChangeNotifier {
  AppLog({this.capacity = 500, this.mirrorToConsole = true})
    : assert(capacity > 0);
  static final instance = AppLog();
  static const maxTranscriptRunes = 16000;
  final int capacity;
  final bool mirrorToConsole;
  final _clock = Stopwatch()..start();
  final _entries = <AppLogEntry>[];
  int _nextId = 0;
  bool _scheduled = false, _disposed = false;
  Duration get elapsed => _clock.elapsed;
  List<AppLogEntry> get entries => List.unmodifiable(_entries);
  static const detailLabels = <String, String>{
    'topicLoading': '載入主題',
    'topicSelection': '選擇主題',
    'introduction': '自我介紹',
    'question': '分享回憶',
    'imageGenerating': '產生回憶圖片',
    'evaluation': '確認圖片',
    'revisionRecording': '說明修圖要求',
    'revisionGenerating': '修改圖片',
    'summary': '摘要',
    'idle': '待命',
    'preparing': '準備錄音',
    'recording': '錄音中',
    'stopping': '停止中',
    'completed': '完成',
    'failed': '失敗',
    'manual': '手動停止',
    'silence': '停頓停止',
    'maximumDuration': '錄音時間上限',
    'cancelled': '取消',
    'interrupted': '中斷',
    'timeout': '逾時',
    'network': '連線錯誤',
    'server': '服務錯誤',
    'authentication': '認證錯誤',
    'invalidAudio': '音檔格式錯誤',
    'invalidResponse': '回應格式錯誤',
    'incomplete': '辨識未完整結束',
    'payloadTooLarge': '請求過大',
    'configuration': '設定錯誤',
    'unsupportedCapability': '不支援的功能',
    'rateLimit': '請求頻率限制',
    'billing': '額度／付款錯誤',
    'unexpected': '未分類錯誤',
    'tw': '台語',
    'zh': '中文',
    'debugAudio': '測試音檔',
    'processing': '處理',
    'noSpeech': '尚未開口',
    'disposed': '結束流程',
    'invalidInput': '輸入格式錯誤',
    'tailo': '台語備援：LLM 轉台羅',
    'legacyServer': '台語備援：舊伺服器',
    'tailoSkipped': '台語備援：未設定轉台羅模型的 API Key，略過 LLM',
    'sttBackendRefused': '成大 STT 後端辨識伺服器拒絕連線（伺服器端問題）',
    'sttBackendTimeout': '成大 STT 後端辨識伺服器逾時（伺服器端問題）',
    'sttBackendError': '成大 STT 後端回報錯誤',
  };
  void record(
    LogArea area,
    LogEvent event, {
    int? operationId,
    int? durationMs,
    int? bytes,
    int? complete,
    int? total,
    int? statusCode,
    String? detail,
  }) {
    if (_disposed) return;
    final entry = AppLogEntry(
      id: ++_nextId,
      time: DateTime.now(),
      elapsed: elapsed,
      area: area,
      event: event,
      operationId: operationId,
      durationMs: durationMs,
      bytes: bytes,
      complete: complete,
      total: total,
      statusCode: statusCode,
      detail: detail == null
          ? null
          : detailLabels.containsKey(detail)
          ? detail
          : 'unexpected',
    );
    _append(entry);
  }

  /// Only recognized speech is accepted here, never prompts or raw responses.
  void recordTranscription(
    String text, {
    required int operationId,
    bool partial = false,
  }) {
    if (_disposed) return;
    final runes = text.runes.take(maxTranscriptRunes + 1).toList();
    final truncated = runes.length > maxTranscriptRunes;
    _append(
      AppLogEntry(
        id: ++_nextId,
        time: DateTime.now(),
        elapsed: elapsed,
        area: LogArea.stt,
        event: partial ? LogEvent.partialTranscription : LogEvent.transcription,
        operationId: operationId,
        transcript: String.fromCharCodes(runes.take(maxTranscriptRunes)),
        transcriptTruncated: truncated,
      ),
    );
  }

  void _append(AppLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > capacity) _entries.removeAt(0);
    if (mirrorToConsole && kDebugMode) debugPrint(entry.line);
    _changed();
  }

  String exportText() => _entries.map((e) => e.line).join('\n');
  void clear() {
    _entries.clear();
    _changed();
  }

  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clock.stop();
    super.dispose();
  }
}
