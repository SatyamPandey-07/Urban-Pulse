/// An HTML page (the Leaflet live map) that Dart drives with JavaScript.
///
/// On Android and iOS it is a WebView; in a browser it is an `<iframe>` whose
/// functions are called directly, since the web WebView cannot run scripts in
/// its page. Both expose the same [HtmlMapController].
library;

export 'html_map_io.dart' if (dart.library.js_interop) 'html_map_web.dart';
