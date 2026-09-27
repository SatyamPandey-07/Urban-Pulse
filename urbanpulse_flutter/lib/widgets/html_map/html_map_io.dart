import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The page in a WebView (Android, iOS).
class HtmlMapController {
  HtmlMapController({required String html, required Color background, required VoidCallback onLoaded, String? baseUrl}) {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(background)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => onLoaded()))
      ..loadHtmlString(html, baseUrl: baseUrl);
  }

  late final WebViewController _web;

  Future<void> run(String script) => _web.runJavaScript(script);

  /// The map takes every gesture inside it, so dragging pans the map.
  Widget view() => WebViewWidget(
    controller: _web,
    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    },
  );

  void dispose() {}
}
