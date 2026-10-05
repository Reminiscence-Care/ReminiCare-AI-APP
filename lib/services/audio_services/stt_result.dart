enum SttErrorKind {
  payloadTooLarge,
  authentication,
  invalidAudio,
  network,
  timeout,
  server,
  invalidResponse,
}

class SttException implements Exception {
  const SttException(this.kind, this.message);
  final SttErrorKind kind;
  final String message;
  @override
  String toString() => 'SttException($kind): $message';
}

class SttResult {
  const SttResult({this.text = '', this.error});
  final String text;
  final SttException? error;
  bool get isSilent => error == null && text.isEmpty;
}

abstract interface class ProgressSttService {
  void Function(int complete, int total)? get onProgress;
  set onProgress(void Function(int complete, int total)? value);
  void forget(String path);
}
