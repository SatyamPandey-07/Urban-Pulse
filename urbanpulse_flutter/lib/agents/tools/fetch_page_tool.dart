import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/data/data_cache.dart';
import '../../services/data/http_util.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import 'agent_tool.dart';
import 'web_search_tool.dart';

/// Reads a web page as plain text: through Tavily's extract when a key is
/// available (it handles JS-heavy pages), else a direct polite fetch with the
/// HTML stripped down. Cached, budgeted, and restricted to public http(s) URLs.
class FetchPageTool extends AgentTool {
  FetchPageTool({
    required this.budget,
    this.tavily,
    http.Client? client,
    DataCache? cache,
    this.maxChars = 6000,
  }) : _client = client ?? http.Client(),
       _cache = cache ?? MemoryCache();

  final ToolBudget budget;
  final TavilySearchProvider? tavily;
  final http.Client _client;
  final DataCache _cache;

  /// How much text is returned to the model.
  final int maxChars;

  @override
  String get name => 'fetch_page';

  @override
  String get description =>
      'Read one web page (a hotel page, an article, a review thread) as plain text.';

  @override
  String get argsHelp => 'url: string';

  @override
  Future<ToolOutput> run(Map<String, Object?> args, {AgentKind? caller}) async {
    final raw = args['url'];
    if (raw is! String) return ToolOutput.failure('missing "url"');
    final uri = safeUri(raw);
    if (uri == null) return ToolOutput.failure('that URL is not allowed');
    final url = uri.toString();

    final hit = await _cache.get('fetch.$url');
    if (hit != null) return _output(url, hit);

    String? text;
    var via = 'direct fetch';
    if (tavily != null && tavily!.available && budget.trySpendFetch()) {
      final pages = await tavily!.extract([url]);
      final t = pages?[url];
      if (t != null && t.trim().isNotEmpty) {
        text = t;
        via = 'Tavily extract';
      } else {
        budget.refundFetch();
      }
    }
    if (text == null) {
      final o = await httpGet(
        _client,
        uri,
        headers: const {
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en',
        },
        timeout: const Duration(seconds: 12),
      );
      if (!o.ok) {
        return ToolOutput.failure(o.error ?? 'HTTP ${o.status}');
      }
      text = htmlToText(o.body!);
    }

    text = text.trim();
    if (text.isEmpty) return ToolOutput.failure('the page had no readable text');
    await _cache.put('fetch.$url', jsonEncode({'t': text, 'v': via}), ttl: const Duration(hours: 24));
    return _output(url, jsonEncode({'t': text, 'v': via}));
  }

  ToolOutput _output(String url, String cached) {
    String text;
    String via;
    try {
      final m = jsonDecode(cached) as Map<String, dynamic>;
      text = m['t'] as String;
      via = m['v'] as String? ?? 'fetch';
    } catch (_) {
      text = cached;
      via = 'fetch';
    }
    final shown = text.length > maxChars ? '${text.substring(0, maxChars)}…' : text;
    return ToolOutput(
      ok: true,
      text: shown,
      data: text,
      sources: [Provenance(source: via, url: url, confidence: 0.7)],
    );
  }

  /// Only public http(s) URLs. Blocks localhost, private and link-local
  /// addresses: the URL may have been written by a model steered by user text.
  static Uri? safeUri(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return null;
    final host = u.host.toLowerCase();
    if (host.isEmpty || !host.contains('.')) return null;
    if (host == 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) return null;
    final ip = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (ip != null) {
      final a = int.parse(ip.group(1)!);
      final b = int.parse(ip.group(2)!);
      if (a == 10 || a == 127 || a == 0 || (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)) {
        return null;
      }
    }
    if (host.contains(':') || host.startsWith('[')) return null;
    return u;
  }

  /// A dependable, dependency-free HTML to text: drops scripts, styles and page
  /// chrome, keeps block structure as line breaks, decodes common entities.
  static String htmlToText(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    for (final tag in ['script', 'style', 'noscript', 'svg', 'nav', 'footer', 'header', 'form', 'iframe']) {
      s = s.replaceAll(RegExp('<$tag[\\s\\S]*?</$tag>', caseSensitive: false), ' ');
    }
    final title = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1);
    s = s.replaceAll(RegExp(r'<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)[^>]*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _decodeEntities(s);
    s = s.replaceAll(RegExp(r'[ \t ]+'), ' ').replaceAll(RegExp(r'\s*\n\s*'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    final t = title == null ? '' : '${_decodeEntities(title).trim()}\n\n';
    return '$t${s.trim()}';
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1)!);
        return code == null || code > 0x10FFFF ? ' ' : String.fromCharCode(code);
      });
}
