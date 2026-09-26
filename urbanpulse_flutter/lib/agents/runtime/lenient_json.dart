import 'dart:convert';

/// Parses the JSON a language model *meant* to write. Models wrap JSON in
/// prose and code fences, leave trailing commas, use curly quotes, or get cut
/// off mid-object; none of that should sink an agent. Returns null only when
/// nothing usable can be recovered.
Object? parseLenientJson(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;

  // Prefer the content of a fenced block when there is one.
  final fence = RegExp(r'```(?:json|JSON)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();

  final candidate = _balancedSlice(text);
  if (candidate == null) return null;

  for (final attempt in _repairs(candidate)) {
    try {
      return jsonDecode(attempt);
    } catch (_) {
      // try the next repair
    }
  }
  return null;
}

/// [parseLenientJson] constrained to a JSON object.
Map<String, dynamic>? parseLenientObject(String raw) {
  final v = parseLenientJson(raw);
  return v is Map<String, dynamic> ? v : null;
}

/// [parseLenientJson] constrained to a JSON array.
List<dynamic>? parseLenientList(String raw) {
  final v = parseLenientJson(raw);
  return v is List<dynamic> ? v : null;
}

/// From the first `{` or `[` to its matching close, honouring strings. If the
/// text is cut off, everything from the opener to the end is returned so the
/// repairs can close it.
String? _balancedSlice(String text) {
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '{' || c == '[') {
      start = i;
      break;
    }
  }
  if (start < 0) return null;

  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final c = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{' || c == '[') {
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return text.substring(start);
}

/// Progressively more aggressive fixes, cheapest first.
Iterable<String> _repairs(String s) sync* {
  yield s;

  final basic = s
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'//[^\n"]*\n'), '\n');
  yield basic;

  final noTrailingCommas = basic.replaceAllMapped(
    RegExp(r',\s*([}\]])'),
    (m) => m.group(1)!,
  );
  yield noTrailingCommas;

  yield _closeOpenBrackets(noTrailingCommas);
}

/// Closes an unterminated string and any brackets left open by a truncated reply.
String _closeOpenBrackets(String s) {
  final stack = <String>[];
  var inString = false;
  var escaped = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      stack.add('}');
    } else if (c == '[') {
      stack.add(']');
    } else if ((c == '}' || c == ']') && stack.isNotEmpty) {
      stack.removeLast();
    }
  }
  final out = StringBuffer(s);
  if (inString) out.write('"');
  // Drop a dangling comma or colon before closing.
  var body = out.toString().replaceAll(RegExp(r'[,:]\s*$'), '');
  // A dangling key with no value ("key":) is closed as null.
  if (RegExp(r'"\s*$').hasMatch(body) && stack.isNotEmpty && stack.last == '}') {
    final lastQuote = body.lastIndexOf('"', body.length - 2);
    final before = lastQuote > 0 ? body.substring(0, lastQuote).trimRight() : '';
    if (before.endsWith('{') || before.endsWith(',')) {
      body = body.substring(0, lastQuote).trimRight();
      body = body.replaceAll(RegExp(r',\s*$'), '');
    }
  }
  for (final closer in stack.reversed) {
    body += closer;
  }
  return body;
}
