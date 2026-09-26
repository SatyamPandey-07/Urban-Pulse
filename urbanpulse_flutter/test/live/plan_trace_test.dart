@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/agent_toolkit.dart';
import 'package:urbanpulse/agents/runtime/llm_pool.dart';
import 'package:urbanpulse/agents/runtime/task_graph.dart';
import 'package:urbanpulse/agents/yatri/planner_orchestrator.dart';
import 'package:urbanpulse/core/config.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';

import 'live_recorder.dart';

/// Live runs of the whole planner against the real services, printing the task
/// graph, the feed, the model calls and the days, so a failure can be traced to
/// the agent that caused it. Skipped unless a real Groq key is compiled in:
///
///   flutter test test/live --dart-define-from-file=config.json
///
/// One scenario: add `--plain-name "goa"` (or "jaipur", "munnar").
void main() {
  final skip = AppConfig.hasGroqKey ? false : 'needs a Groq key: --dart-define-from-file=config.json';
  final start = DateTime.now().add(const Duration(days: 10));
  DateTime at(int day, int hour) => DateTime(start.year, start.month, start.day + day, hour);

  TripBrief brief(String id, {required String destination, required String origin, required int days, int budget = 60000, Set<AccessibilityNeed> needs = const {}, Map<String, Set<String>> details = const {}, int adults = 2, int seniors = 0, TripPace pace = TripPace.balanced}) => TripBrief(
    id: id,
    createdAt: DateTime.now(),
    destination: destination,
    originCity: origin,
    start: at(0, 7),
    end: at(days - 1, 20),
    travellerCount: adults + seniors,
    adults: adults,
    seniors: seniors,
    children: 0,
    budgetMaxInr: budget,
    transportModes: const {TripTransportMode.train, TripTransportMode.carTaxi},
    accessibilityNeeds: needs.isEmpty ? const {AccessibilityNeed.none} : needs,
    accessibilityConfirmed: true,
    accessibilityDetails: details,
    pace: pace,
    style: TripStyle.heritage,
  );

  final scenarios = {
    'goa: 3 days from Mumbai, no needs': brief('live_goa', destination: 'Goa', origin: 'Mumbai', days: 3),
    'jaipur: 4 days, wheelchair + elderly + walking under 100 m': brief(
      'live_jaipur',
      destination: 'Jaipur',
      origin: 'Delhi',
      days: 4,
      seniors: 2,
      needs: const {AccessibilityNeed.wheelchair, AccessibilityNeed.elderlyCare, AccessibilityNeed.limitedMobility},
      details: const {
        'a11y.mobility.walking': {'lt100'},
        'a11y.mobility.support': {'avoid_stairs', 'rest_stops'},
        'a11y.elderly.support': {'ground_floor', 'slow_pace'},
      },
      pace: TripPace.relaxed,
    ),
    'munnar: 3 days, tight budget': brief('live_munnar', destination: 'Munnar', origin: 'Kochi', days: 3, budget: 12000),
  };

  // The report file for each scenario, written next to fixes.md.
  const reportFiles = {'goa': 'live-run-goa.md', 'jaipur': 'live-run-jaipur-wheelchair.md', 'munnar': 'live-run-munnar.md'};

  for (final MapEntry(key: name, value: b) in scenarios.entries) {
    test(name, () async {
      final llm = RecordingLlm(LlmPool.fromConfig());
      final client = RecordingClient(http.Client());
      final tk = AgentToolkit.fromConfig(llm: llm, client: client);
      final asked = <String>[];
      final dialogue = <Map<String, Object?>>[];
      late PlannerOrchestrator orchestrator;
      orchestrator = PlannerOrchestrator(
        toolkit: tk,
        ask: (q) async {
          asked.add('${q.id}: ${q.defaultText}\n      options: ${q.options.map((o) => '${o.recommended ? '*' : ''}${o.label}').join(' | ')}');
          final a = autoAnswer(q);
          dialogue.add({'question': toPlain(q), 'answer': toPlain(a)});
          return a;
        },
      );
      final startedAt = DateTime.now();
      final sw = Stopwatch()..start();
      final outcome = await orchestrator.run(b);
      sw.stop();
      printTrace(name, orchestrator, outcome, asked, tk, sw.elapsed);
      final file = '../${reportFiles[name.split(':').first]}';
      writeFile(file, report(name, b, orchestrator, outcome, dialogue, llm, client, startedAt, sw.elapsed));
      // ignore: avoid_print
      print('report written to $file');
    }, skip: skip, timeout: Timeout.none);
  }
}

/// What a traveller who accepts every recommendation would answer.
YatriAnswer autoAnswer(YatriQuestion q) {
  final recommended = [for (final o in q.options) if (o.recommended) o];
  if (q.widget == AnswerWidget.multiSelect) {
    final picks = recommended.isEmpty ? q.options.take(1).toList() : recommended;
    return MultiChoiceAnswer({for (final o in picks) o.id}, [for (final o in picks) o.label]);
  }
  final o = recommended.isNotEmpty ? recommended.first : q.options.first;
  return ChoiceAnswer(o.id, o.label);
}

void printTrace(String name, PlannerOrchestrator o, PlanOutcome outcome, List<String> asked, AgentToolkit tk, Duration wall) {
  final out = StringBuffer()
    ..writeln('\n======== $name ========')
    ..writeln('status: ${outcome.status.name} · ${outcome.summary}')
    ..writeln('wall time: ${wall.inSeconds}s · active (plan clock): ${o.clock.elapsed.inSeconds}s')
    ..writeln('\n-- task graph --');
  for (final n in o.graph.nodes) {
    out.writeln('${n.status.name.padRight(12)} ${'${n.elapsed?.inSeconds ?? '-'}s'.padLeft(5)}  ${n.spec.id.padRight(28)} ${n.summary ?? ''}');
  }
  out.writeln('\n-- warnings and decisions --');
  for (final e in o.graph.events) {
    if (e.kind == FeedKind.warn || e.kind == FeedKind.ask || e.kind == FeedKind.decide) {
      out.writeln('[${e.kind.name}] ${e.agent.name}: ${e.text}');
    }
  }
  out.writeln('\n-- questions --');
  for (final q in asked) {
    out.writeln('  $q');
  }
  final llm = tk.llm;
  if (llm is LlmPool) {
    out.writeln('\n-- model calls --');
    final byAgent = <AgentKind, List<LlmCallRecord>>{};
    for (final c in llm.calls) {
      byAgent.putIfAbsent(c.agent, () => []).add(c);
    }
    for (final MapEntry(key: a, value: calls) in byAgent.entries) {
      final failed = calls.where((c) => !c.ok).map((c) => c.failure?.name).toList();
      final secs = calls.fold<int>(0, (s, c) => s + c.duration.inMilliseconds) ~/ 1000;
      out.writeln('${a.name.padRight(10)} ${calls.length} calls, ${secs}s total${failed.isEmpty ? '' : ', failed: $failed'}');
    }
  }
  out.writeln('\n-- days --');
  final it = outcome.itinerary;
  if (it == null) {
    out.writeln('NO ITINERARY');
  } else {
    for (final d in it.days) {
      final visits = [for (final s in d.slots) if (s.kind == SlotKind.visit) s.title];
      out.writeln('day ${d.number} (${d.title}): ${visits.length} visits${visits.isEmpty ? '' : ': ${visits.join(', ')}'}');
    }
    final stays = [?it.hotel, ...it.hotelAlternatives];
    final reviewed = stays.where((h) => h.claims.any((c) => c.isReviews)).length;
    out.writeln('stay: ${it.hotel?.name ?? 'none'} · stays with reviews: $reviewed of ${stays.length} · sources: ${it.sources.length}');
  }
  if (outcome.notes.isNotEmpty) out.writeln('\nnotes: ${outcome.notes.join(' | ')}');
  // ignore: avoid_print
  print(out);
}

/// Everything the run produced, as it came back, for reading and checking.
String report(String name, TripBrief brief, PlannerOrchestrator o, PlanOutcome outcome, List<Map<String, Object?>> dialogue, RecordingLlm llm, RecordingClient client, DateTime startedAt, Duration wall) {
  final it = outcome.itinerary;
  final b = StringBuffer()
    ..writeln('# Live run: $name')
    ..writeln()
    ..writeln('Run on ${startedAt.toIso8601String()} against the real services (Groq, Tavily, TomTom, OpenStreetMap, Wikipedia, Open-Meteo, Xotelo), '
        'calling `PlannerOrchestrator.run` directly: no chat screen. Every question was answered automatically with the '
        'recommended option (or the first one), the way a traveller who accepts every suggestion would.')
    ..writeln()
    ..writeln('Re-run with: `flutter test test/live --dart-define-from-file=config.json --plain-name "${name.split(':').first}"` (from `urbanpulse_flutter/`).')
    ..writeln()
    ..writeln('| | |')
    ..writeln('|---|---|')
    ..writeln('| Outcome | **${outcome.status.name}**: ${outcome.summary} |')
    ..writeln('| Wall time | ${wall.inSeconds} s (plan clock, excluding waits on the traveller: ${o.clock.elapsed.inSeconds} s) |')
    ..writeln('| Task graph | ${o.graph.nodes.length} nodes, ${o.graph.events.length} feed events |')
    ..writeln('| Questions asked | ${dialogue.length} |')
    ..writeln('| Model calls | ${llm.calls.length} (${llm.calls.where((c) => (c['response'] as Map?)?['ok'] == false).length} failed after retries) |')
    ..writeln('| HTTP calls | ${client.calls.length} |')
    ..writeln()
    ..writeln('Long strings (page text, model reasoning) are cut at $maxString characters and marked where cut. Keys in URLs are redacted.')
    ..writeln()
    ..writeln('## Contents')
    ..writeln('1. [Brief (input)](#1-brief-input)')
    ..writeln('2. [Outcome](#2-outcome)')
    ..writeln('3. [Days at a glance](#3-days-at-a-glance)')
    ..writeln('4. [Task graph](#4-task-graph)')
    ..writeln('5. [Agent reports, by node](#5-agent-reports-by-node)')
    ..writeln('6. [Feed](#6-feed)')
    ..writeln('7. [Questions and answers](#7-questions-and-answers)')
    ..writeln('8. [Itinerary object](#8-itinerary-object)')
    ..writeln('9. [Model calls](#9-model-calls)')
    ..writeln('10. [HTTP calls](#10-http-calls)')
    ..writeln()
    ..writeln('## 1. Brief (input)')
    ..writeln(jsonBlock(brief))
    ..writeln('## 2. Outcome')
    ..writeln(jsonBlock(outcome))
    ..writeln('## 3. Days at a glance')
    ..writeln();
  if (it == null) {
    b.writeln('No itinerary was produced.\n');
  } else {
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    String cell(String? s) => (s ?? '').replaceAll('|', '/').replaceAll('\n', ' ');
    for (final d in it.days) {
      b.writeln('**Day ${d.number} (${d.date.toIso8601String().substring(0, 10)}): ${d.title}**${d.weather == null ? '' : ' · ${d.weather}'}');
      b.writeln();
      b.writeln('| Time | Kind | What | Access | Cost (₹) | Note |');
      b.writeln('|---|---|---|---|---|---|');
      for (final s in d.slots) {
        b.writeln('| ${hm(s.start)}–${hm(s.end)} | ${s.kind.name} | ${cell(s.title)} | ${s.access?.name ?? ''} | ${s.costInr ?? ''} | ${cell([...s.flags, ?s.note].join(' · '))} |');
      }
      b.writeln();
    }
    final leg = it.chosenTransport;
    b.writeln('Stay: ${it.hotel?.name ?? 'none'} · Journey: ${leg == null ? 'none' : '${leg.mode.label}, ${leg.durationMin} min each way'} · Total: ₹${it.budget.totalInr}');
    b.writeln();
    b.writeln('Assumptions and notes:');
    for (final a in it.assumptions) {
      b.writeln('- $a');
    }
    b.writeln();
  }
  b
    ..writeln('## 4. Task graph')
    ..writeln()
    ..writeln('| # | Node | Agent | Status | Time | Delegated by | Parents | Summary |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  final nodes = o.graph.nodes;
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    b.writeln('| ${i + 1} | `${n.id}` | ${n.agent.name} | ${n.status.name} | ${n.elapsed?.inSeconds ?? '-'} s | ${n.delegatedBy ?? ''} | ${n.spec.parents.join(', ')} | ${(n.summary ?? '').replaceAll('|', '/')} |');
  }
  b
    ..writeln()
    ..writeln('All nodes as objects:')
    ..writeln(jsonBlock(nodes))
    ..writeln('## 5. Agent reports, by node')
    ..writeln()
    ..writeln('What each task returned to the task that started it (`TaskBoard.reports`), payload included.')
    ..writeln();
  for (final e in o.board.reports.entries) {
    b
      ..writeln('<details><summary><code>${e.key}</code>: ${e.value.status.name}, ${e.value.summary.replaceAll('<', '&lt;')}</summary>')
      ..writeln()
      ..writeln(jsonBlock(e.value))
      ..writeln('</details>')
      ..writeln();
  }
  b
    ..writeln('## 6. Feed')
    ..writeln()
    ..writeln('Every event, in order, as shown under the graph in the app.')
    ..writeln(jsonBlock(o.graph.events))
    ..writeln('## 7. Questions and answers')
    ..writeln()
    ..writeln('Each question the planner put to the traveller, and the answer the automatic traveller gave.')
    ..writeln(jsonBlock(dialogue))
    ..writeln('## 8. Itinerary object')
    ..writeln()
    ..writeln('`Itinerary.toJson()`, exactly as the app receives it.')
    ..writeln(jsonBlock(it))
    ..writeln('## 9. Model calls')
    ..writeln()
    ..writeln("Every call an agent made to the model pool: the request messages and the response (the final one, after the pool's own key and model failover).")
    ..writeln();
  for (final c in llm.calls) {
    final r = c['response'] as Map?;
    b
      ..writeln('<details><summary>#${c['index']} ${c['agent']} · ${c['tier']} · ${r?['ok'] == true ? 'ok (${r?['model']})' : 'FAILED ${r?['kind']}'} · ${c['durationMs']} ms</summary>')
      ..writeln()
      ..writeln(jsonBlock(c))
      ..writeln('</details>')
      ..writeln();
  }
  final pool = llm.inner;
  if (pool is LlmPool) {
    b
      ..writeln('Every attempt inside the pool (each key and model tried):')
      ..writeln(jsonBlock([
        for (final a in pool.calls) {'agent': a.agent, 'model': a.model, 'keySlot': a.slot, 'durationMs': a.duration.inMilliseconds, 'ok': a.ok, 'failure': a.failure},
      ]));
  }
  b
    ..writeln('## 10. HTTP calls')
    ..writeln()
    ..writeln('Every request the data clients made (maps, hotels, search, weather, Wikipedia), with the response body. Model calls are in section 9.')
    ..writeln();
  for (final c in client.calls) {
    final url = c['url'] as String;
    b
      ..writeln('<details><summary>#${c['index']} ${c['method']} ${c['status'] ?? c['error']} · ${c['durationMs']} ms · ${url.length > 110 ? '${url.substring(0, 110)}…' : url}</summary>')
      ..writeln()
      ..writeln(jsonBlock(c))
      ..writeln('</details>')
      ..writeln();
  }
  return b.toString();
}
