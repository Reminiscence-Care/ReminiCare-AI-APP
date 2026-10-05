import 'dart:convert';

String? extractProviderMessageText(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) return null;
  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map<String, dynamic>) {
      final message = first['message'];
      if (message is Map<String, dynamic>) {
        final content = _contentText(message['content']);
        if (content != null && content.isNotEmpty) return content;
        // Private reasoning is not a final answer, even when content is empty.
      }
      final text = _contentText(first['text']);
      if (text != null && text.isNotEmpty) return text;
    }
  }
  return _contentText(decoded['output_text']);
}

Map<String, dynamic> decodeJsonObjectFromText(
  String text, {
  String? requiredKey,
}) {
  final candidates = _balancedJsonObjects(text).toList().reversed;
  for (final candidate in candidates) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic> &&
          (requiredKey == null || decoded.containsKey(requiredKey))) {
        return decoded;
      }
    } catch (_) {
      // Models may emit several drafts. Continue with the next complete object.
    }
  }
  throw const FormatException('找不到完整的 JSON object');
}

String? _contentText(dynamic value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is List) {
    final parts = <String>[];
    for (final part in value) {
      if (part is String && part.trim().isNotEmpty) {
        parts.add(part.trim());
      } else if (part is Map) {
        final text = part['text'] ?? part['content'];
        if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
      }
    }
    return parts.isEmpty ? null : parts.join('\n');
  }
  return null;
}

Iterable<String> _balancedJsonObjects(String text) sync* {
  var start = -1;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = 0; index < text.length; index++) {
    final code = text.codeUnitAt(index);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5C) {
        escaped = true;
      } else if (code == 0x22) {
        inString = false;
      }
      continue;
    }
    if (code == 0x22 && depth > 0) {
      inString = true;
    } else if (code == 0x7B) {
      if (depth == 0) start = index;
      depth++;
    } else if (code == 0x7D && depth > 0) {
      depth--;
      if (depth == 0 && start >= 0) {
        yield text.substring(start, index + 1);
        start = -1;
      }
    }
  }
}
