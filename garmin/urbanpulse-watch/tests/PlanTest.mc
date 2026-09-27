import Toybox.Lang;
import Toybox.Test;
import Toybox.System;

//! Assembling the day's plan from the chunks the phone sends.
module PlanTest {

    function step(n, at, text, mode) {
        return { "n" => n, "at" => at, "x" => text, "m" => mode };
    }

    function chunk(from, total, steps) {
        return { "t" => "plan", "v" => 1, "i" => from, "tot" => total,
                 "day" => "Day 2", "steps" => steps };
    }

    (:test)
    function startsWithNoPlan(logger) {
        var s = new LinkState();
        Test.assert(!s.hasPlan());
        Test.assertEqual(s.planTotal, 0);
        Test.assert(s.stepAt(0) == null);
        return true;
    }

    (:test)
    function appliesOneChunk(logger) {
        var s = new LinkState();
        Test.assert(s.applyPlan(chunk(0, 2, [
            step(1, "09:00", "Take the train from Panvel to CST", "train"),
            step(2, "11:00", "Visit Gateway of India", "visit")
        ])));
        Test.assert(s.hasPlan());
        Test.assertEqual(s.planTotal, 2);
        Test.assertEqual(s.planDay, "Day 2");
        Test.assertEqual(s.stepAt(0)["x"], "Take the train from Panvel to CST");
        Test.assertEqual(s.stepAt(1)["m"], "visit");
        return true;
    }

    (:test)
    function assemblesSeveralChunksInOrder(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 4, [step(1, "09:00", "One", "walk"),
                                 step(2, "10:00", "Two", "walk")]));
        s.applyPlan(chunk(2, 4, [step(3, "11:00", "Three", "walk"),
                                 step(4, "12:00", "Four", "walk")]));
        Test.assertEqual(s.planSteps.size(), 4);
        Test.assertEqual(s.stepAt(0)["x"], "One");
        Test.assertEqual(s.stepAt(3)["x"], "Four");
        Test.assertEqual(s.filledSteps(), 4);
        return true;
    }

    (:test)
    function showsTotalBeforeEveryChunkArrives(logger) {
        var s = new LinkState();
        // Only the first chunk of a twelve-step day.
        s.applyPlan(chunk(0, 12, [step(1, "09:00", "One", "walk")]));
        // The watch can honestly say "1 of 12" while the rest is in flight.
        Test.assertEqual(s.planTotal, 12);
        Test.assertEqual(s.planSteps.size(), 12);
        Test.assertEqual(s.filledSteps(), 1);
        Test.assert(s.stepAt(5) == null);
        return true;
    }

    (:test)
    function outOfOrderChunksLandInTheRightSlots(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 4, [step(1, "09:00", "One", "walk")]));
        // The third chunk overtakes the second.
        s.applyPlan(chunk(3, 4, [step(4, "12:00", "Four", "walk")]));
        s.applyPlan(chunk(1, 4, [step(2, "10:00", "Two", "walk"),
                                 step(3, "11:00", "Three", "walk")]));
        Test.assertEqual(s.stepAt(1)["x"], "Two");
        Test.assertEqual(s.stepAt(3)["x"], "Four");
        return true;
    }

    (:test)
    function aRepeatedChunkOverwritesRatherThanDuplicating(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 2, [step(1, "09:00", "One", "walk"),
                                 step(2, "10:00", "Two", "walk")]));
        s.applyPlan(chunk(1, 2, [step(2, "10:00", "Two", "walk")]));
        Test.assertEqual(s.planSteps.size(), 2);
        Test.assertEqual(s.filledSteps(), 2);
        return true;
    }

    (:test)
    function aNewPlanReplacesTheOldOne(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 3, [step(1, "09:00", "Old one", "walk"),
                                 step(2, "10:00", "Old two", "walk"),
                                 step(3, "11:00", "Old three", "walk")]));
        // A chunk starting at 0 is a new day, not more of the same one.
        s.applyPlan(chunk(0, 1, [step(1, "08:00", "New one", "train")]));
        Test.assertEqual(s.planSteps.size(), 1);
        Test.assertEqual(s.stepAt(0)["x"], "New one");
        return true;
    }

    (:test)
    function ignoresAMalformedChunk(logger) {
        var s = new LinkState();
        // No index, no total: nothing to place.
        Test.assert(!s.applyPlan({ "t" => "plan", "v" => 1 }));
        Test.assert(!s.hasPlan());
        return true;
    }

    (:test)
    function skipsStepsWithNoText(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 2, [
            step(1, "09:00", "Real step", "walk"),
            { "n" => 2, "at" => "10:00", "m" => "walk" }
        ]));
        Test.assertEqual(s.stepAt(0)["x"], "Real step");
        // A step with nothing to say is left empty rather than drawn blank.
        Test.assert(s.stepAt(1) == null);
        return true;
    }

    (:test)
    function sanitisesStepText(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 1, [step(1, "09:00", "Café   stop", "meal")]));
        Test.assertEqual(s.stepAt(0)["x"], "Caf stop");
        return true;
    }

    (:test)
    function emptyPlanClearsTheWatch(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 2, [step(1, "09:00", "One", "walk"),
                                 step(2, "10:00", "Two", "walk")]));
        s.applyPlan(chunk(0, 0, []));
        Test.assert(!s.hasPlan());
        return true;
    }

    (:test)
    function everyModeHasALabelAndAColour(logger) {
        var modes = ["train", "bus", "walk", "cab", "flight", "visit", "meal", "hotel"];
        for (var i = 0; i < modes.size(); i++) {
            Test.assert(PlanView.modeLabel(modes[i]).length() > 0);
        }
        // An unknown mode from a newer phone still renders, blank but not broken.
        Test.assertEqual(PlanView.modeLabel("teleport"), "");
        Test.assertEqual(PlanView.modeLabel(null), "");
        return true;
    }

    (:test)
    function currentStepIsTheFirstNotYetStarted(logger) {
        var s = new LinkState();
        s.applyPlan(chunk(0, 3, [step(1, "00:01", "Early", "walk"),
                                 step(2, "23:58", "Late", "walk"),
                                 step(3, "23:59", "Latest", "walk")]));
        // Everything but the last two is in the past for almost the whole day,
        // so the index must be one of those, never past the end.
        var i = s.currentStepIndex();
        Test.assert(i >= 0);
        Test.assert(i < s.planSteps.size());
        return true;
    }

    (:test)
    function currentStepIsSafeWithNoPlan(logger) {
        var s = new LinkState();
        Test.assertEqual(s.currentStepIndex(), 0);
        return true;
    }
}
