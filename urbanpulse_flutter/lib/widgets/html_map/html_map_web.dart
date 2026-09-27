import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// The page in an `<iframe srcdoc>` (browsers). A srcdoc frame shares the
/// app's origin, so its `window.setCenter(...)` and friends are called
/// directly. Scripts sent before the page has loaded wait for it.
class HtmlMapController {
  HtmlMapController({required String html, required Color background, required VoidCallback onLoaded, String? baseUrl})
    : _viewType = 'urbanpulse-html-map-${_nextId++}' {
    _frame = web.HTMLIFrameElement()
      ..srcdoc = html.toJS
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = _css(background);
    _frame.onLoad.listen((_) {
      _loaded = true;
      for (final s in _pending) {
        _eval(s);
      }
      _pending.clear();
      onLoaded();
    });
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _frame);
  }

  static int _nextId = 0;

  final String _viewType;
  late final web.HTMLIFrameElement _frame;
  final List<String> _pending = [];
  bool _loaded = false;

  Future<void> run(String script) async {
    if (!_loaded) {
      _pending.add(script);
      return;
    }
    _eval(script);
  }

  void _eval(String script) {
    final window = _frame.contentWindow;
    if (window == null) return;
    try {
      (window as JSObject).callMethod<JSAny?>('eval'.toJS, script.toJS);
    } catch (_) {
      // a failed map call never breaks the screen
    }
  }

  Widget view() => HtmlElementView(viewType: _viewType);

  void dispose() => _pending.clear();

  static String _css(Color c) =>
      'rgba(${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()}, ${c.a.toStringAsFixed(3)})';
}
