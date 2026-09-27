import Toybox.Lang;
import Toybox.Test;
import Toybox.System;

//! Message parsing. Run with:
//!   monkeyc -f monkey.jungle -d fr965 -o bin/test.prg -t -y <key>
//!   monkeydo bin/test.prg fr965 -t
module ProtocolTest {

    (:test)
    function acceptsOurVersion(logger) {
        Test.assert(Protocol.accepts({ "t" => "state", "v" => 1 }));
        return true;
    }

    (:test)
    function rejectsNewerVersion(logger) {
        // A newer phone talking protocol 2 must be ignored, not half-parsed.
        Test.assert(!Protocol.accepts({ "t" => "state", "v" => 2 }));
        return true;
    }

    (:test)
    function rejectsMissingVersion(logger) {
        Test.assert(!Protocol.accepts({ "t" => "state" }));
        return true;
    }

    (:test)
    function rejectsStringVersion(logger) {
        // "1" is not 1; a JSON bridge that stringifies numbers must not sneak in.
        Test.assert(!Protocol.accepts({ "t" => "state", "v" => "1" }));
        return true;
    }

    (:test)
    function rejectsNonDictionary(logger) {
        Test.assert(!Protocol.accepts("state"));
        Test.assert(!Protocol.accepts(null));
        Test.assert(!Protocol.accepts([1, 2, 3]));
        return true;
    }

    (:test)
    function typeOfReadsT(logger) {
        Test.assertEqual(Protocol.typeOf({ "t" => "alert", "v" => 1 }), "alert");
        Test.assertEqual(Protocol.typeOf({ "t" => 7, "v" => 1 }), null);
        Test.assertEqual(Protocol.typeOf({ "v" => 1 }), null);
        return true;
    }

    (:test)
    function numAcceptsFloatsAndRejectsStrings(logger) {
        Test.assertEqual(Protocol.num({ "d" => 412 }, "d"), 412);
        Test.assertEqual(Protocol.num({ "d" => 412.4 }, "d"), 412);
        Test.assertEqual(Protocol.num({ "d" => "412" }, "d"), null);
        Test.assertEqual(Protocol.num({ }, "d"), null);
        return true;
    }

    (:test)
    function boolFallsBack(logger) {
        Test.assert(Protocol.bool({ "live" => true }, "live", false));
        Test.assert(!Protocol.bool({ "live" => "yes" }, "live", false));
        Test.assert(Protocol.bool({ }, "live", true));
        return true;
    }

    (:test)
    function strRejectsEmpty(logger) {
        Test.assertEqual(Protocol.str({ "id" => "" }, "id"), null);
        Test.assertEqual(Protocol.str({ "id" => "a1" }, "id"), "a1");
        Test.assertEqual(Protocol.str({ "id" => 5 }, "id"), null);
        return true;
    }

    (:test)
    function sanitiseKeepsAscii(logger) {
        Test.assertEqual(Protocol.sanitise("Gateway of India", 60), "Gateway of India");
        return true;
    }

    (:test)
    function sanitiseCollapsesWhitespace(logger) {
        Test.assertEqual(Protocol.sanitise("  Leave   now  ", 60), "Leave now");
        return true;
    }

    (:test)
    function sanitiseReplacesNonAscii(logger) {
        // A codepoint the watch font cannot draw becomes a space, and the
        // collapse then removes it rather than leaving a gap.
        var out = Protocol.sanitise("Café stop", 60);
        Test.assertEqual(out, "Caf stop");
        return true;
    }

    (:test)
    function sanitiseTruncatesOnWord(logger) {
        var out = Protocol.sanitise("Leave now for the Gateway of India", 20);
        Test.assert(out.length() <= 20);
        // The cut is marked, so a clipped line reads as clipped.
        Test.assert(out.substring(out.length() - 3, out.length()).equals("..."));
        return true;
    }

    (:test)
    function truncateLeavesShortTextAlone(logger) {
        Test.assertEqual(Protocol.truncate("short", 20), "short");
        return true;
    }

    (:test)
    function truncateHandlesOneLongWord(logger) {
        // No space to break on: it must still fit, not collapse to "...".
        var out = Protocol.truncate("aaaaaaaaaaaaaaaaaaaaaaaa", 10);
        Test.assertEqual(out.length(), 10);
        return true;
    }

    (:test)
    function truncateHandlesTinyBudget(logger) {
        Test.assertEqual(Protocol.truncate("abcdef", 2).length(), 2);
        return true;
    }

    (:test)
    function outboundMessagesCarryVersion(logger) {
        Test.assertEqual(Protocol.hello("fr965", "1.0.0")["v"], 1);
        Test.assertEqual(Protocol.sos(1700000000)["t"], "sos");
        Test.assertEqual(Protocol.sosCancel()["t"], "sosCancel");
        Test.assertEqual(Protocol.ack("a1")["id"], "a1");
        return true;
    }
}
