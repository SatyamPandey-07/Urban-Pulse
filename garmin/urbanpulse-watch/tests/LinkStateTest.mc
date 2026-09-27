import Toybox.Lang;
import Toybox.Test;
import Toybox.System;

//! The state model, and above all the stale-state rule.
module LinkStateTest {

    function stateMessage(title, at, dist) {
        var next = { "title" => title, "at" => at };
        if (dist != null) {
            next["dist"] = dist;
        }
        return { "t" => "state", "v" => 1, "live" => true, "next" => next,
                 "day" => "Day 2", "ts" => 1700000000 };
    }

    (:test)
    function startsWaiting(logger) {
        var s = new LinkState();
        // Nothing received: the view shows "Waiting for phone" and no numbers.
        Test.assert(s.isWaiting());
        Test.assertEqual(s.ageS(), null);
        Test.assert(!s.isStale());
        Test.assertEqual(s.nextTitle, null);
        return true;
    }

    (:test)
    function appliesState(logger) {
        var s = new LinkState();
        s.applyState(stateMessage("Gateway of India", "14:20", 1200));
        Test.assert(!s.isWaiting());
        Test.assert(s.live);
        Test.assertEqual(s.nextTitle, "Gateway of India");
        Test.assertEqual(s.nextAt, "14:20");
        Test.assertEqual(s.nextDistM, 1200);
        Test.assertEqual(s.day, "Day 2");
        return true;
    }

    (:test)
    function freshStateIsNotStale(logger) {
        var s = new LinkState();
        s.applyState(stateMessage("Elephanta Caves", "09:05", 400));
        // Just received, so age is ~0 and well inside the 5 minute window.
        Test.assert(!s.isStale());
        Test.assert(s.ageS() < LinkState.STALE_AFTER_S);
        return true;
    }

    (:test)
    function staleAfterFiveMinutes(logger) {
        var s = new LinkState();
        s.applyState(stateMessage("Elephanta Caves", "09:05", 400));
        // Backdate the receipt past the window. The age is measured against the
        // watch's own monotonic timer, not the phone's `ts`, so this is the only
        // thing that needs moving.
        s.receivedAtMs = System.getTimer() - (LinkState.STALE_AFTER_S + 30) * 1000;
        Test.assert(s.isStale());
        // The data is kept, not discarded: greyed and labelled, per the rule.
        Test.assertEqual(s.nextTitle, "Elephanta Caves");
        Test.assert(s.ageText().length() > 0);
        return true;
    }

    (:test)
    function ageTextReadsInMinutes(logger) {
        var s = new LinkState();
        s.applyState(stateMessage("Colaba", "11:00", null));
        s.receivedAtMs = System.getTimer() - 7 * 60 * 1000;
        Test.assertEqual(s.ageText(), "7 min ago");
        return true;
    }

    (:test)
    function missingDistanceStaysMissing(logger) {
        var s = new LinkState();
        s.applyState(stateMessage("Colaba Causeway", "11:00", null));
        // The watch must not derive a distance the phone did not send.
        Test.assertEqual(s.nextDistM, null);
        Test.assertEqual(LinkState.distanceText(null, false), null);
        return true;
    }

    (:test)
    function negativeDistanceIsDropped(logger) {
        var s = new LinkState();
        s.applyState(stateMessage("Colaba", "11:00", -5));
        Test.assertEqual(s.nextDistM, null);
        return true;
    }

    (:test)
    function stateWithoutNextClearsTheStop(logger) {
        var s = new LinkState();
        s.applyState(stateMessage("Gateway", "14:20", 900));
        s.applyState({ "t" => "state", "v" => 1, "live" => false, "ts" => 1700000900 });
        Test.assertEqual(s.nextTitle, null);
        Test.assertEqual(s.nextAt, null);
        Test.assertEqual(s.nextDistM, null);
        Test.assert(!s.live);
        return true;
    }

    (:test)
    function sanitisesTitleOnArrival(logger) {
        var s = new LinkState();
        var long = "A stop with a very long name that goes past the sixty character budget easily";
        s.applyState(stateMessage(long, "10:00", 100));
        Test.assert(s.nextTitle.length() <= Protocol.MAX_LINE);
        return true;
    }

    (:test)
    function newAlertIsShown(logger) {
        var s = new LinkState();
        var shown = s.applyAlert({ "t" => "alert", "v" => 1, "id" => "a1",
                                   "kind" => "leave", "text" => "Leave now for the ferry" });
        Test.assert(shown);
        Test.assertEqual(s.alertId, "a1");
        Test.assertEqual(s.alertKind, "leave");
        Test.assertEqual(s.alertText, "Leave now for the ferry");
        return true;
    }

    (:test)
    function repeatedAlertIdIsNotShownTwice(logger) {
        var s = new LinkState();
        var first = s.applyAlert({ "t" => "alert", "v" => 1, "id" => "a1",
                                   "kind" => "leave", "text" => "Leave now" });
        var second = s.applyAlert({ "t" => "alert", "v" => 1, "id" => "a1",
                                    "kind" => "leave", "text" => "Leave now" });
        Test.assert(first);
        // A re-delivered alert must not buzz again.
        Test.assert(!second);
        return true;
    }

    (:test)
    function alertWithoutIdOrTextIsIgnored(logger) {
        var s = new LinkState();
        Test.assert(!s.applyAlert({ "t" => "alert", "v" => 1, "kind" => "leave", "text" => "hi" }));
        Test.assert(!s.applyAlert({ "t" => "alert", "v" => 1, "id" => "a2", "kind" => "leave" }));
        Test.assertEqual(s.alertText, null);
        return true;
    }

    (:test)
    function alertMemoryIsBounded(logger) {
        var s = new LinkState();
        // Past the ring buffer, the oldest id is forgotten and would show again.
        for (var i = 0; i < LinkState.RECENT_ALERTS + 3; i++) {
            s.applyAlert({ "t" => "alert", "v" => 1, "id" => "id" + i.toString(),
                           "kind" => "meal", "text" => "Lunch" });
        }
        Test.assert(s.applyAlert({ "t" => "alert", "v" => 1, "id" => "id0",
                                   "kind" => "meal", "text" => "Lunch" }));
        return true;
    }

    (:test)
    function acceptsKnownSosStatuses(logger) {
        var s = new LinkState();
        Test.assert(s.applySosAck({ "t" => "sosAck", "v" => 1, "status" => "countdown",
                                    "secondsLeft" => 7 }));
        Test.assert(s.sosIsCounting());
        Test.assertEqual(s.sosSecondsLeft, 7);

        Test.assert(s.applySosAck({ "t" => "sosAck", "v" => 1, "status" => "prepared",
                                    "detail" => "Tap send on the phone" }));
        Test.assert(!s.sosIsCounting());
        Test.assertEqual(s.sosStatus, "prepared");
        return true;
    }

    (:test)
    function rejectsUnknownSosStatus(logger) {
        var s = new LinkState();
        // An invented status would render as a blank headline; refuse it and keep
        // whatever the phone last actually said.
        Test.assert(!s.applySosAck({ "t" => "sosAck", "v" => 1, "status" => "delivered" }));
        Test.assertEqual(s.sosStatus, null);
        return true;
    }

    (:test)
    function sosStatusTextNeverClaimsSentForPrepared(logger) {
        var s = new LinkState();
        s.applySosAck({ "t" => "sosAck", "v" => 1, "status" => "prepared" });
        var text = SosView.statusText(s);
        // "prepared" means a composer is open. It must not read as "sent".
        Test.assert(text.find("sent") == null);
        Test.assertEqual(text, "SOS ready on phone");
        return true;
    }

    (:test)
    function distanceTextMetric(logger) {
        Test.assertEqual(LinkState.distanceText(420, false), "420 m");
        Test.assertEqual(LinkState.distanceText(1200, false), "1.2 km");
        return true;
    }

    (:test)
    function distanceTextStatute(logger) {
        Test.assertEqual(LinkState.distanceText(100, true), "328 ft");
        Test.assertEqual(LinkState.distanceText(8047, true), "5.0 mi");
        return true;
    }

    (:test)
    function alertLabelsCoverEveryKind(logger) {
        Test.assertEqual(AlertView.labelFor(Protocol.KIND_LEAVE), "LEAVE NOW");
        Test.assertEqual(AlertView.labelFor(Protocol.KIND_ARRIVED), "ARRIVED");
        Test.assertEqual(AlertView.labelFor(Protocol.KIND_LATE), "RUNNING BEHIND");
        Test.assertEqual(AlertView.labelFor(Protocol.KIND_MEAL), "MEAL");
        Test.assertEqual(AlertView.labelFor(Protocol.KIND_RAIN), "RAIN");
        // An unknown kind from a future phone still renders something neutral.
        Test.assertEqual(AlertView.labelFor("volcano"), "UPDATE");
        Test.assertEqual(AlertView.labelFor(null), "UPDATE");
        return true;
    }
}
