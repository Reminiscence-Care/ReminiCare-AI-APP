import 'dart:typed_data';

/// Validated 16 kHz mono PCM. Splits cover every sample exactly once.
class WavAudio {
  WavAudio(this.pcm);
  final Uint8List pcm;
  static const bytesPerSecond = 32000;
  double get seconds => pcm.length / bytesPerSecond;

  factory WavAudio.parse(Uint8List bytes) {
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('錄音不是有效的 WAV');
    }
    var offset = 12;
    var validFormat = false;
    final chunks = BytesBuilder();
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = ByteData.sublistView(
        bytes,
      ).getUint32(offset + 4, Endian.little);
      var start = offset + 8;
      if (start + size > bytes.length) throw const FormatException('WAV 音訊不完整');
      if (id == 'fmt ') {
        if (size < 16) throw const FormatException('WAV 格式不完整');
        final data = ByteData.sublistView(bytes, start, start + size);
        validFormat =
            data.getUint16(0, Endian.little) == 1 &&
            data.getUint16(2, Endian.little) == 1 &&
            data.getUint32(4, Endian.little) == 16000 &&
            data.getUint16(14, Endian.little) == 16;
      } else if (id == 'data') {
        // record_windows 1.0.7 rewrites the Media Foundation WAV header
        // with a shorter WAVEFORMATEX header. Its original fmt/data headers
        // remain before the PCM, outside the declared data length. Recover
        // only this exact layout, never treat arbitrary trailing bytes as PCM.
        if (validFormat && offset == 38 && bytes.length == start + size + 36) {
          final remaining = ByteData.sublistView(bytes);
          final originalFmt = start + 2;
          final originalData = start + 28;
          bool tagAt(int position, String tag) =>
              String.fromCharCodes(bytes.sublist(position, position + 4)) ==
              tag;
          if (remaining.getUint16(start, Endian.little) == 0 &&
              tagAt(originalFmt, 'fmt ') &&
              remaining.getUint32(originalFmt + 4, Endian.little) == 18 &&
              remaining.getUint16(36, Endian.little) == 0 &&
              List.generate(
                18,
                (i) => i,
              ).every((i) => bytes[20 + i] == bytes[originalFmt + 8 + i]) &&
              tagAt(originalData, 'data') &&
              remaining.getUint32(originalData + 4, Endian.little) == size &&
              remaining.getUint32(4, Endian.little) == size + 40) {
            start += 36;
          }
        }
        chunks.add(bytes.sublist(start, start + size));
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }
    if (offset != bytes.length) {
      throw const FormatException('WAV 尾端區塊不完整');
    }
    final pcm = chunks.takeBytes();
    if (!validFormat || pcm.isEmpty || pcm.length.isOdd) {
      throw const FormatException('錄音需為 16kHz 單聲道 16-bit PCM，且包含音訊');
    }
    return WavAudio(pcm);
  }

  Uint8List encode() {
    final header = ByteData(44);
    void tag(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        header.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    tag(36, 'data');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, bytesPerSecond, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder()
          ..add(header.buffer.asUint8List())
          ..add(pcm))
        .takeBytes();
  }

  List<WavAudio> split({int maximumBytes = 5 * bytesPerSecond}) {
    final segments = <WavAudio>[];
    var start = 0;
    while (start < pcm.length) {
      var end = (start + maximumBytes).clamp(0, pcm.length);
      if (end < pcm.length) {
        // Find a low-energy 20 ms window in the last 0.5 s, keeping >1 s.
        final data = ByteData.sublistView(pcm);
        var bestEnergy = double.infinity;
        var bestEnd = end;
        for (
          var candidate = (end - 16000).clamp(start + 32000, end);
          candidate <= end;
          candidate += 640
        ) {
          var energy = 0.0;
          for (var i = candidate - 640; i < candidate; i += 2) {
            energy += data.getInt16(i, Endian.little).abs();
          }
          if (energy < bestEnergy) {
            bestEnergy = energy;
            bestEnd = candidate;
          }
        }
        end = bestEnd;
      }
      segments.add(WavAudio(Uint8List.sublistView(pcm, start, end)));
      start = end;
    }
    return segments;
  }
}
