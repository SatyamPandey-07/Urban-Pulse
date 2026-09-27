import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';

// ---------------------------------------------------------------------------
// Recording

/// The microphone, behind an interface so voice can be driven in tests.
abstract class MicRecorder {
  /// Starts recording; false if the microphone cannot be used (no permission).
  Future<bool> start();

  /// Stops and returns 16 kHz mono 16-bit PCM, or null if nothing was captured.
  Future<Uint8List?> stop();

  Future<void> cancel();
  Future<void> dispose();
}

class DeviceMic implements MicRecorder {
  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  static const sampleRate = 16000;

  @override
  Future<bool> start() async {
    try {
      if (!await _rec.hasPermission()) return false;
      _buf.clear();
      final stream = await _rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: 1));
      _sub = stream.listen(_buf.add, onError: (_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> stop() async {
    try {
      await _rec.stop();
      await _sub?.cancel();
      _sub = null;
      final bytes = _buf.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _sub?.cancel();
      _sub = null;
      _buf.clear();
      await _rec.cancel();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await cancel();
    try {
      await _rec.dispose();
    } catch (_) {}
  }
}

/// Wraps raw 16-bit mono PCM as a WAV file.
Uint8List wavFromPcm16(Uint8List pcm, {int sampleRate = 16000, int channels = 1}) {
  final header = ByteData(44);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
}

/// Loudness of 16-bit PCM, 0 (silence) to 1.
double pcmLevel(Uint8List pcm) {
  final samples = pcm.length ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(pcm);
  var sum = 0.0;
  // Every 8th sample is plenty to tell speech from silence.
  var n = 0;
  for (var i = 0; i < samples; i += 8) {
    final v = data.getInt16(i * 2, Endian.little) / 32768;
    sum += v * v;
    n++;
  }
  return n == 0 ? 0 : math.sqrt(sum / n);
}

// ---------------------------------------------------------------------------
// Transcription (Groq Whisper)

sealed class Transcription {
  const Transcription();
}

class Transcript extends Transcription {
  const Transcript(this.text);

  final String text;
}

class TranscriptionFailed extends Transcription {
  const TranscriptionFailed(this.message);

  final String message;
}

abstract class Transcriber {
  bool get available;
  Future<Transcription> transcribe(Uint8List wav);
}

class GroqTranscriber implements Transcriber {
  GroqTranscriber({http.Client? client, List<String>? keys, this.model = 'whisper-large-v3-turbo'}) : _client = client ?? http.Client(), _keys = keys;

  static const endpoint = 'https://api.groq.com/openai/v1/audio/transcriptions';

  final http.Client _client;
  final List<String>? _keys;
  final String model;

  List<String> get keys => _keys ?? AppConfig.groqKeys;

  @override
  bool get available => keys.isNotEmpty;

  @override
  Future<Transcription> transcribe(Uint8List wav) async {
    final all = keys;
    if (all.isEmpty) return const TranscriptionFailed('Voice needs a Groq key.');
    var message = 'The speech service could not be reached.';
    // A key that is rate limited or rejected hands over to the next one.
    for (final key in all) {
      try {
        final req = http.MultipartRequest('POST', Uri.parse(endpoint))
          ..headers['Authorization'] = 'Bearer $key'
          ..fields['model'] = model
          ..fields['response_format'] = 'json'
          ..fields['temperature'] = '0'
          ..files.add(http.MultipartFile.fromBytes('file', wav, filename: 'speech.wav'));
        final res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 30)));
        if (res.statusCode == 429 || res.statusCode == 401 || res.statusCode == 403) {
          message = res.statusCode == 429 ? 'The speech service is busy. Try again in a moment.' : 'The speech service rejected the key.';
          continue;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          message = 'The speech service could not understand that recording.';
          continue;
        }
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        final text = j is Map && j['text'] is String ? (j['text'] as String).trim() : '';
        return text.isEmpty ? const TranscriptionFailed('I could not make out any words.') : Transcript(text);
      } catch (_) {
        message = 'The speech service could not be reached.';
      }
    }
    return TranscriptionFailed(message);
  }
}

// ---------------------------------------------------------------------------
// Speaking

abstract class Speaker {
  Future<void> speak(String text);
  Future<void> stop();
}

class DeviceSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {}
  }

  @override
  Future<void> speak(String text) async {
    final clean = speechText(text);
    if (clean.isEmpty) return;
    try {
      await _init();
      await _tts.stop();
      await _tts.speak(clean);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Text made fit to be read aloud: no links, markdown marks or emoji, and a
/// sensible length.
String speechText(String raw, {int maxChars = 420}) {
  var s = raw
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'[*_`#>~|]+'), ' ')
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true), '')
      .replaceAll('₹', 'rupees ')
      .replaceAll('CO₂', 'carbon dioxide')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > maxChars) {
    final cut = s.substring(0, maxChars);
    final end = cut.lastIndexOf(RegExp(r'[.!?]'));
    s = end > maxChars ~/ 2 ? cut.substring(0, end + 1) : cut;
  }
  return s;
}

// ---------------------------------------------------------------------------
// The whole thing

enum VoiceState { idle, recording, transcribing }

/// Talk to the app: tap to speak, tap again to send; the words come back as
/// text through the callback. Also reads replies aloud when that is switched on.
class VoiceService extends ChangeNotifier {
  VoiceService({MicRecorder? mic, Transcriber? transcriber, Speaker? speaker, SharedPreferences? prefs, this.maxRecording = const Duration(seconds: 60)})
    : _mic = mic ?? DeviceMic(),
      _transcriber = transcriber ?? GroqTranscriber(),
      _speaker = speaker ?? DeviceSpeaker(),
      _prefs = prefs {
    speakReplies = prefs?.getBool(_prefKey) ?? false;
  }

  static const _prefKey = 'voice.speak_replies';

  final MicRecorder _mic;
  final Transcriber _transcriber;
  final Speaker _speaker;
  final SharedPreferences? _prefs;
  final Duration maxRecording;

  VoiceState state = VoiceState.idle;

  /// The last problem, in words for the traveller; cleared by the next attempt.
  String? error;
  bool speakReplies = false;

  void Function(String text)? _deliver;
  Timer? _limit;
  bool _disposed = false;

  /// Whether speech can be sent to Groq (a key exists).
  bool get canTranscribe => _transcriber.available;
  bool get recording => state == VoiceState.recording;
  bool get busy => state != VoiceState.idle;

  /// Starts listening, or (when already listening) stops and sends the words on
  /// to [onText].
  Future<void> toggle(void Function(String text) onText) async {
    if (state == VoiceState.transcribing) return;
    if (state == VoiceState.recording) {
      await _finish();
      return;
    }
    error = null;
    if (!_transcriber.available) {
      error = 'Voice needs a Groq key in the app settings.';
      _notify();
      return;
    }
    await _speaker.stop();
    _deliver = onText;
    final ok = await _mic.start();
    if (!ok) {
      error = 'Microphone access is needed to talk. Allow it in your phone settings.';
      _notify();
      return;
    }
    state = VoiceState.recording;
    _limit = Timer(maxRecording, _finish);
    _notify();
  }

  Future<void> _finish() async {
    _limit?.cancel();
    if (state != VoiceState.recording) return;
    state = VoiceState.transcribing;
    _notify();
    final pcm = await _mic.stop();
    final deliver = _deliver;
    if (pcm == null || pcm.length < 16000 * 2 * 0.4) {
      _fail('That was too short. Tap the mic and speak, then tap again.');
      return;
    }
    if (pcmLevel(pcm) < 0.004) {
      _fail('I did not hear anything. Try again a little closer to the microphone.');
      return;
    }
    final result = await _transcriber.transcribe(wavFromPcm16(pcm));
    if (_disposed) return;
    switch (result) {
      case Transcript(:final text):
        state = VoiceState.idle;
        error = null;
        _notify();
        deliver?.call(text);
      case TranscriptionFailed(:final message):
        _fail(message);
    }
  }

  void _fail(String message) {
    state = VoiceState.idle;
    error = message;
    _notify();
  }

  /// Stops recording without sending anything.
  Future<void> cancel() async {
    _limit?.cancel();
    if (state == VoiceState.idle) return;
    await _mic.cancel();
    state = VoiceState.idle;
    _notify();
  }

  Future<void> setSpeakReplies(bool on) async {
    speakReplies = on;
    if (!on) await _speaker.stop();
    await _prefs?.setBool(_prefKey, on);
    _notify();
  }

  /// Reads [text] aloud, if replies are switched to be spoken.
  Future<void> sayReply(String text) async {
    if (speakReplies && !recording) await _speaker.speak(text);
  }

  /// Reads [text] aloud regardless of the switch (turn-by-turn directions).
  Future<void> say(String text) => _speaker.speak(text);

  Future<void> hush() => _speaker.stop();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _limit?.cancel();
    _mic.dispose();
    _speaker.stop();
    super.dispose();
  }
}
