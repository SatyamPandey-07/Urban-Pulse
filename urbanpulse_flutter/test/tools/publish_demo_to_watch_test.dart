// Publishes the demo itinerary to the watch endpoint, so the Garmin app can be
// driven end-to-end without the phone app running.
//
// It is a test file only because the model layer reaches into Flutter, so a
// plain `dart run` cannot load it. It skips itself unless you point it at a
// server, which is what keeps it out of a normal test run:
//
//   cd server && npm start
//   WATCH_DEMO_SERVER=http://localhost:3001 WATCH_DEMO_CODE=DEMO42 \
//     flutter test test/tools/publish_demo_to_watch_test.dart
//
// Then enter the same code and server URL in the watch app's settings (Garmin
// Connect on a real watch; the simulator's Settings Editor in development).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/services/watch_payload.dart';

import '../fixtures/demo_itinerary.dart';

void main() {
  final server = Platform.environment['WATCH_DEMO_SERVER'];
  final code = Platform.environment['WATCH_DEMO_CODE'] ?? 'DEMO42';

  test('publishes the demo itinerary for pairing code $code', () async {
    // The plan is anchored to today, so the watch has a live "now" and "next".
    final payload = buildWatchPayload(demoItinerary());
    final body = jsonEncode(payload);

    final client = HttpClient();
    try {
      final request = await client.putUrl(Uri.parse('$server/api/watch/$code'));
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close();
      final replyBody = await response.transform(utf8.decoder).join();

      stdout.writeln('PUT $server/api/watch/$code -> ${response.statusCode} $replyBody');
      stdout.writeln('${payload['t']}, ${(payload['d'] as List).length} days, '
          '${utf8.encode(body).length} bytes');

      expect(response.statusCode, 200);
    } finally {
      client.close();
    }
  }, skip: server == null ? 'set WATCH_DEMO_SERVER to publish' : null);
}
