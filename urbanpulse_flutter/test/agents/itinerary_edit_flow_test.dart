import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/editor/edit_ops.dart';
import 'package:urbanpulse/agents/editor/itinerary_editor.dart';
import 'package:urbanpulse/agents/yatri/planner_orchestrator.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/state/itinerary_edit_controller.dart';

import '../yatri/test_support.dart';
import 'hotel_world.dart';
import 'itinerary_editor_test.dart' show autoAnswer, editor, world, visitTitles;
import 'planner_orchestrator_test.dart' show toolkitFor;

Set<String> _allVisits(Itinerary it) => {for (final d in it.days) ...visitTitles(d)};

void main() {
  late Itinerary base;
  final places = {'munnar': munnarCenter, 'pune': bengaluruCenter};

  setUpAll(() async {
    final o = PlannerOrchestrator(toolkit: toolkitFor(world(), places: places), ask: autoAnswer);
    base = (await o.run(completeBrief())).itinerary!;
  });

  group('the edit controller', () {
    test('a request, its diff, undo and redo', () async {
      final saved = <int>[];
      final c = ItineraryEditController(
        toolkit: toolkitFor(world(), places: places),
        itinerary: base,
        onChanged: (it) async => saved.add(it.version),
      );
      addTearDown(c.dispose);
      expect(c.canUndo, isFalse);

      await c.send('remove ${_allVisits(base).first}');
      expect(c.busy, isFalse);
      expect(c.messages.first.fromUser, isTrue);
      expect(c.current.version, 2);
      expect(c.messages.last.diff, isNotNull);
      expect(saved, [2]);
      expect(c.canUndo, isTrue);

      await c.undo();
      expect(c.current.version, 1);
      expect(_allVisits(c.current), _allVisits(base));
      expect(c.canRedo, isTrue);
      expect(saved, [2, 1]);

      await c.redo();
      expect(c.current.version, 2);
      expect(_allVisits(c.current).length, _allVisits(base).length - 1);
    });

    test('a chip runs known operations without a model', () async {
      final c = ItineraryEditController(toolkit: toolkitFor(world(), places: places), itinerary: base);
      addTearDown(c.dispose);
      expect(c.chips, isNotEmpty);
      await c.run([SetPreferencesOp(sustainability: SustainabilityPriority.greenest)], label: 'Make it greener');
      expect(c.messages.length, greaterThanOrEqualTo(2));
      expect(c.busy, isFalse);
    });

    test('a failed or unclear request leaves the plan and the history alone', () async {
      final c = ItineraryEditController(toolkit: toolkitFor(world(), places: places), itinerary: base);
      addTearDown(c.dispose);
      await c.send('qwerty asdf');
      expect(c.current.version, 1);
      expect(c.canUndo, isFalse);
      expect(c.messages.last.fromUser, isFalse);
    });

    test('a plan without its trip details is not editable and says so', () async {
      final bare = Itinerary.fromJson({...base.toJson()..remove('brief')});
      final d = ItineraryEditController(toolkit: toolkitFor(world(), places: places), itinerary: bare);
      addTearDown(d.dispose);
      expect(d.editable, isFalse);
      await d.send('more rest on day 2');
      expect(d.current.version, 1);
      expect(d.messages.last.failed, isTrue);
    });

    test('undo keeps at most five versions', () async {
      final c = ItineraryEditController(toolkit: toolkitFor(world(), places: places), itinerary: base);
      addTearDown(c.dispose);
      for (var i = 0; i < 7; i++) {
        await c.run([SetPreferencesOp(pace: i.isEven ? TripPace.relaxed : TripPace.packed)], label: 'pace $i');
      }
      var undone = 0;
      while (c.canUndo) {
        await c.undo();
        undone++;
      }
      expect(undone, lessThanOrEqualTo(ItineraryEditController.maxUndo));
    });

    test('disposing while a request runs is harmless', () async {
      final c = ItineraryEditController(toolkit: toolkitFor(world(), places: places), itinerary: base);
      final f = c.send('more rest on day 2');
      c.dispose();
      await f;
    });
  });

  group('chaos: random operations never break a plan', () {
    test('60 random edits in a row keep the plan valid', () async {
      final rnd = Random(7);
      var it = base;
      final names = _allVisits(base).toList();
      for (var i = 0; i < 60; i++) {
        final n = it.days.length;
        final name = names[rnd.nextInt(names.length)];
        final day = 1 + rnd.nextInt(n);
        final List<EditOp> ops = switch (rnd.nextInt(9)) {
          0 => [RestDayOp(day, rnd.nextBool() ? RestLevel.light : RestLevel.free)],
          1 => [MoveStopOp(_idOf(it, name) ?? 'zzz', day)],
          2 => [RemoveStopOp(_idOf(it, name) ?? 'zzz')],
          3 => [SwapStopOp(_idOf(it, name) ?? 'zzz')],
          4 => [LockStopOp(_idOf(it, name) ?? 'zzz', lock: rnd.nextBool())],
          5 => [ChangeDatesOp(deltaDays: rnd.nextBool() ? 1 : -1)],
          6 => [SetPreferencesOp(pace: TripPace.values[rnd.nextInt(TripPace.values.length)])],
          7 => [SetPreferencesOp(budgetFactor: 0.7 + rnd.nextDouble() * 0.6)],
          _ => [RestDayOp(day + 5, RestLevel.light), RestDayOp(0, RestLevel.free)],
        };
        final out = await editor().apply(it, ops, request: 'chaos $i');
        if (out.status == EditStatus.applied) it = out.itinerary!;
        expect(it.days, isNotEmpty);
        // a day never holds the same place twice, and no place is on two days
        final seen = <String>{};
        for (final d in it.days) {
          for (final s in d.slots) {
            if (s.kind != SlotKind.visit || s.refId == null) continue;
            expect(seen.add(s.refId!), isTrue, reason: 'duplicate ${s.title} after edit $i: ${out.say}');
          }
        }
        for (var k = 0; k < it.days.length; k++) {
          expect(it.days[k].number, k + 1);
        }
      }
    });
  });
}

String? _idOf(Itinerary it, String title) {
  for (final d in it.days) {
    for (final s in d.slots) {
      if (s.kind == SlotKind.visit && s.title == title) return s.refId;
    }
  }
  return null;
}
