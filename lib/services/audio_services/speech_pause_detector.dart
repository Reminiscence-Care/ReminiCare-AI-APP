/// Receives elapsed monotonic time after calibration; avoids timer tick drift.
class SpeechPauseDetector {
  SpeechPauseDetector({
    required this.silenceTimeout,
    this.idleTimeout = const Duration(seconds: 15),
  });
  final Duration silenceTimeout;
  final Duration idleTimeout;
  bool hasSpoken = false;
  int _loudSamples = 0;
  Duration _lastVoice = Duration.zero;
  bool sample({required Duration elapsed, required bool loud}) {
    if (loud) {
      if (++_loudSamples >= 2) hasSpoken = true;
      if (hasSpoken) _lastVoice = elapsed;
      return false;
    }
    _loudSamples = 0;
    return hasSpoken
        ? elapsed - _lastVoice >= silenceTimeout
        : elapsed >= idleTimeout;
  }
}
