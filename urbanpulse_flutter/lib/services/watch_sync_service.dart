import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../models/itinerary/itinerary.dart';
import 'watch_payload.dart';

enum WatchSyncState { idle, sending, sent, failed }

/// Publishes the finished itinerary where the Garmin watch can fetch it.
///
/// There is no companion-app channel here on purpose: the watch reads the same
/// Urban Pulse registry the rest of the app already talks to
/// (`PUT /api/watch/<code>` from here, `GET /api/watch/<code>` from the watch),
/// so nothing platform-specific is needed on either side and the plan survives
/// the phone being locked or out of Bluetooth range.
///
/// The pairing code is generated once per install and typed into the watch app's
/// settings in Garmin Connect. That is the whole pairing ceremony.
///
/// No method throws: a watch that cannot be reached must never be able to break
/// the planner that calls this.
class WatchSyncService extends ChangeNotifier {
  WatchSyncService(
    this._prefs, {
    http.Client? client,
    String? baseUrl,
    Random? random,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.centralRegistryBaseUrl,
       _random = random ?? Random.secure();

  final SharedPreferences _prefs;
  final http.Client _client;
  final String _baseUrl;
  final Random _random;

  static const _keyCode = 'urbanpulse_watch.pairing_code';
  static const _keyEnabled = 'urbanpulse_watch.enabled';
  static const _keySentAt = 'urbanpulse_watch.last_sent_at';
  static const _keySentWhat = 'urbanpulse_watch.last_sent_summary';

  static const _timeout = Duration(seconds: 6);

  /// No 0/O/1/I: the code gets read off a phone and typed into a watch.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const codeLength = 6;

  WatchSyncState _state = WatchSyncState.idle;
  String? _lastError;

  WatchSyncState get state => _state;
  String? get lastError => _lastError;

  /// On by default: the watch only ever receives anything once the traveller has
  /// entered this code on the watch, so publishing costs nothing until then.
  bool get isEnabled => _prefs.getBool(_keyEnabled) ?? true;

  /// Generated on first read and then stable for the install.
  String get pairingCode {
    final existing = _prefs.getString(_keyCode);
    if (existing != null && existing.length == codeLength) return existing;
    final code = _newCode();
    _prefs.setString(_keyCode, code);
    return code;
  }

  DateTime? get lastSentAt {
    final ms = _prefs.getInt(_keySentAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// e.g. `"Rishikesh, 4 days"` — what the watch is currently showing.
  String? get lastSentSummary => _prefs.getString(_keySentWhat);

  bool get hasPublished => lastSentAt != null;

  Future<void> setEnabled(bool enabled) async {
    await _prefs.setBool(_keyEnabled, enabled);
    if (!enabled) {
      _state = WatchSyncState.idle;
      _lastError = null;
    }
    notifyListeners();
  }

  /// A new code, for a new watch — or to stop an old one from following along.
  Future<String> regenerateCode() async {
    final code = _newCode();
    await _prefs.setString(_keyCode, code);
    await _prefs.remove(_keySentAt);
    await _prefs.remove(_keySentWhat);
    _state = WatchSyncState.idle;
    _lastError = null;
    notifyListeners();
    return code;
  }

  /// Sends the plan to the watch. Called automatically the moment the Yatri
  /// agents finish an itinerary, and from the Send-to-watch action.
  Future<bool> publish(Itinerary itinerary) async {
    if (!isEnabled) return false;

    _state = WatchSyncState.sending;
    _lastError = null;
    notifyListeners();

    try {
      final response = await _client
          .put(
            Uri.parse('$_baseUrl/api/watch/$pairingCode'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(buildWatchPayload(itinerary)),
          )
          .timeout(_timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _prefs.setInt(_keySentAt, DateTime.now().millisecondsSinceEpoch);
        await _prefs.setString(
          _keySentWhat,
          '${itinerary.destination}, ${itinerary.dayCount} '
          'day${itinerary.dayCount == 1 ? '' : 's'}',
        );
        _state = WatchSyncState.sent;
        notifyListeners();
        return true;
      }

      _fail(_messageFor(response));
      return false;
    } catch (e) {
      // Offline, no server, DNS, timeout: the plan is still fine on the phone.
      _fail('Could not reach the Urban Pulse server');
      return false;
    }
  }

  /// Removes the published plan, so a watch still holding the code stops getting
  /// it. The watch keeps whatever it last cached.
  Future<bool> unpublish() async {
    try {
      final response = await _client
          .delete(Uri.parse('$_baseUrl/api/watch/$pairingCode'))
          .timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _prefs.remove(_keySentAt);
        await _prefs.remove(_keySentWhat);
        _state = WatchSyncState.idle;
        _lastError = null;
        notifyListeners();
        return true;
      }
      _fail(_messageFor(response));
      return false;
    } catch (_) {
      _fail('Could not reach the Urban Pulse server');
      return false;
    }
  }

  void _fail(String message) {
    _state = WatchSyncState.failed;
    _lastError = message;
    notifyListeners();
  }

  String _messageFor(http.Response response) {
    if (response.statusCode == 413) return 'That plan is too large for a watch';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) return body['error'] as String;
    } catch (_) {
      // A non-JSON error body tells the traveller nothing useful.
    }
    return 'The server refused the plan (${response.statusCode})';
  }

  String _newCode() => String.fromCharCodes([
    for (var i = 0; i < codeLength; i++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
