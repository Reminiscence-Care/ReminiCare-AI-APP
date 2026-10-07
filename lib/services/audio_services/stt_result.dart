enum SttErrorKind {
  payloadTooLarge,
  authentication,
  invalidAudio,
  network,
  timeout,
  server,
  invalidResponse,
  cancelled,
  incomplete,
}

class SttException implements Exception {
  const SttException(this.kind, this.message, {this.partialText = ''});
  final SttErrorKind kind;
  final String message;
  final String partialText;
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
