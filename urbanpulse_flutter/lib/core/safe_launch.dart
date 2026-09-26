import 'package:url_launcher/url_launcher.dart';

/// Opens a web link found by an agent or a search, but only if it is a plain
/// http(s) URL: pages, model output and listings are untrusted, so anything
/// else (`tel:`, `file:`, `intent:`, `javascript:`) is ignored.
Future<void> openWebLink(String? url) async {
  final uri = safeWebUri(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // no browser available: nothing to do
  }
}

/// [url] as a [Uri] if it is an http(s) URL with a host, else null.
Uri? safeWebUri(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}
