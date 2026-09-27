import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbanpulse/services/voice/voice_service.dart';

/// A recording the test controls.
class ScriptedMic implements MicRecorder {
  bool allow = true;
  Uint8List? pcm;
  bool cancelled = false;

  @override
  Future<bool> start() async => allow;

  @override
  Future<Uint8List?> stop() async => pcm;

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {}
}

class ScriptedTranscriber implements Transcriber {
  Transcription result = const Transcript('hello there');
  int calls = 0;

  @override
  bool available = true;

  @override
  Future<Transcription> transcribe(Uint8List wav) async {
    calls++;
    return result;
  }
}

class ScriptedSpeaker implements Speaker {
  final said = <String>[];

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async {}
}

/// One second of a steady tone, 16 kHz mono 16-bit.
Uint8List tone({int samples = 16000, int amplitude = 8000}) {
  final b = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    b.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  test('a WAV file has the right header and carries the audio', () {
    final wav = wavFromPcm16(tone(samples: 100));
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(wav.length, 44 + 200);
    final h = ByteData.sublistView(wav);
    expect(h.getUint32(24, Endian.little), 16000);
    expect(h.getUint32(40, Endian.little), 200);
  });

  test('silence is told from speech', () {
    expect(pcmLevel(Uint8List(32000)), 0);
    expect(pcmLevel(tone()), greaterThan(0.1));
  });

  test('replies are made fit to be read aloud', () {
    expect(speechText('**Day 2** is lighter 🌿 see https://x.y/z'), 'Day 2 is lighter see');
    expect(speechText('It costs ₹4,000 and CO₂ is low'), 'It costs rupees 4,000 and carbon dioxide is low');
    final long = '${'A sentence here. ' * 60}';
    expect(speechText(long).length, lessThanOrEqualTo(420));
    expect(speechText(long).endsWith('.'), isTrue);
  });

  group('Groq transcription', () {
    test('sends the recording with the key and returns the words', () async {
      late http.BaseRequest seen;
      final t = GroqTranscriber(
        keys: ['k1'],
        client: MockClient.streaming((req, body) async {
          seen = req;
          return http.StreamedResponse(Stream.value(utf8.encode('{"text":" more rest on day two "}')), 200);
        }),
      );
      final r = await t.transcribe(wavFromPcm16(tone()));
      expect((r as Transcript).text, 'more rest on day two');
      expect(seen.headers['Authorization'], 'Bearer k1');
      expect(seen.url.path, endsWith('/audio/transcriptions'));
    });

    test('a busy key hands over to the next one', () async {
      final used = <String>[];
      final t = GroqTranscriber(
        keys: ['a', 'b'],
        client: MockClient.streaming((req, body) async {
          used.add(req.headers['Authorization']!);
          return used.length == 1 ? http.StreamedResponse(const Stream.empty(), 429) : http.StreamedResponse(Stream.value(utf8.encode('{"text":"ok"}')), 200);
        }),
      );
      expect((await t.transcribe(wavFromPcm16(tone())) as Transcript).text, 'ok');
      expect(used, ['Bearer a', 'Bearer b']);
    });

    test('no key, all keys failing, an empty answer and garbage are each a plain message', () async {
      expect(await GroqTranscriber(keys: []).transcribe(Uint8List(10)), isA<TranscriptionFailed>());
      final down = GroqTranscriber(keys: ['a'], client: MockClient.streaming((_, _) async => throw Exception('offline')));
      expect(await down.transcribe(Uint8List(10)), isA<TranscriptionFailed>());
      final empty = GroqTranscriber(keys: ['a'], client: MockClient.streaming((_, _) async => http.StreamedResponse(Stream.value(utf8.encode('{"text":""}')), 200)));
      expect((await empty.transcribe(Uint8List(10)) as TranscriptionFailed).message, contains('words'));
      final junk = GroqTranscriber(keys: ['a'], client: MockClient.streaming((_, _) async => http.StreamedResponse(Stream.value(utf8.encode('nope')), 200)));
      expect(await junk.transcribe(Uint8List(10)), isA<TranscriptionFailed>());
    });
  });

  group('talking to the app', () {
    late ScriptedMic mic;
    late ScriptedTranscriber tr;
    late ScriptedSpeaker speaker;
    late VoiceService v;
    final heard = <String>[];

    setUp(() {
      mic = ScriptedMic()..pcm = tone();
      tr = ScriptedTranscriber();
      speaker = ScriptedSpeaker();
      v = VoiceService(mic: mic, transcriber: tr, speaker: speaker);
      heard.clear();
    });
    tearDown(() => v.dispose());

    test('tap to speak, tap again: the words arrive', () async {
      await v.toggle(heard.add);
      expect(v.state, VoiceState.recording);
      await v.toggle(heard.add);
      expect(v.state, VoiceState.idle);
      expect(heard, ['hello there']);
      expect(v.error, isNull);
    });

    test('no microphone permission says so and does not record', () async {
      mic.allow = false;
      await v.toggle(heard.add);
      expect(v.state, VoiceState.idle);
      expect(v.error, contains('Microphone'));
    });

    test('too short, silent, and failed recordings each explain and send nothing', () async {
      mic.pcm = tone(samples: 1000);
      await v.toggle(heard.add);
      await v.toggle(heard.add);
      expect(v.error, contains('too short'));
      mic.pcm = Uint8List(40000);
      await v.toggle(heard.add);
      await v.toggle(heard.add);
      expect(v.error, contains('did not hear'));
      mic.pcm = tone();
      tr.result = const TranscriptionFailed('The speech service is busy. Try again in a moment.');
      await v.toggle(heard.add);
      await v.toggle(heard.add);
      expect(v.error, contains('busy'));
      expect(heard, isEmpty);
      expect(tr.calls, 1, reason: 'only a real recording is sent');
    });

    test('without a Groq key voice says what it needs', () async {
      tr.available = false;
      await v.toggle(heard.add);
      expect(v.canTranscribe, isFalse);
      expect(v.error, contains('Groq key'));
    });

    test('replies are read aloud only when switched on', () async {
      await v.sayReply('Day 2 is lighter.');
      expect(speaker.said, isEmpty);
      await v.setSpeakReplies(true);
      await v.sayReply('Day 2 is lighter.');
      expect(speaker.said, ['Day 2 is lighter.']);
      await v.say('Turn left');
      expect(speaker.said.last, 'Turn left');
    });

    test('cancelling leaves nothing sent', () async {
      await v.toggle(heard.add);
      await v.cancel();
      expect(v.state, VoiceState.idle);
      expect(mic.cancelled, isTrue);
      expect(heard, isEmpty);
    });

    test('a long recording stops by itself', () async {
      final short = VoiceService(mic: mic, transcriber: tr, speaker: speaker, maxRecording: const Duration(milliseconds: 30));
      addTearDown(short.dispose);
      await short.toggle(heard.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(short.state, VoiceState.idle);
      expect(heard, ['hello there']);
    });
  });
}
