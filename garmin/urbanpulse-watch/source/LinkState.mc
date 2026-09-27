import Toybox.Lang;
import Toybox.System;
import Toybox.Application;

//! Everything the watch knows, and how sure it is of it.
//!
//! The one rule this class exists to enforce: **the watch never shows a number
//! the phone did not send.** With nothing received it says "Waiting for phone".
//! With something received more than [STALE_AFTER_S] ago it still shows it, but
//! greyed and labelled with its age, because a stop that was right five minutes
//! ago is worth seeing and worth doubting.
class LinkState {

    //! State older than this is shown greyed, with its age.
    static const STALE_AFTER_S = 300;

    //! Alerts kept for the ack/duplicate check. Small on purpose: the watch has
    //! kilobytes, and the phone is the real rate limiter.
    static const RECENT_ALERTS = 8;

    //! Most steps of a day the watch will hold. A day longer than this is
    //! truncated rather than risking the memory budget mid-trip.
    static const MAX_STEPS = 40;

    //! Step text is drawn over two lines, so it gets more than a status line.
    static const MAX_STEP_CHARS = 96;

    // --- what the phone last told us -------------------------------------
    var live = false;
    var nextTitle = null;   // String or null
    var nextAt = null;      // "HH:MM" or null
    var nextDistM = null;   // Number or null
    var day = null;         // "Day 2" or null

    //! Epoch seconds from the phone's `ts`, or null if nothing has arrived.
    var stateTs = null;

    //! Monotonic `System.getTimer()` millis when we received it. The phone's
    //! clock and ours can disagree, so age is measured locally.
    var receivedAtMs = null;

    // --- the link ---------------------------------------------------------
    var phoneConnected = false;

    // --- SOS -------------------------------------------------------------
    var sosStatus = null;      // "countdown" | "cancelled" | "sent" | "prepared" | "failed"
    var sosDetail = null;
    var sosSecondsLeft = null;

    // --- alerts ----------------------------------------------------------
    var alertId = null;
    var alertKind = null;
    var alertText = null;

    // --- the day's plan ---------------------------------------------------
    //! Steps received so far, each a dictionary of {n, at, x, m}. Sparse until
    //! every chunk has arrived, which is why `planTotal` is tracked separately:
    //! the watch can honestly show "3 of 12" while still receiving.
    var planSteps = [];

    //! How many steps the day has, as the phone reported it.
    var planTotal = 0;

    //! "Day 2", when the phone sent one.
    var planDay = null;

    //! Monotonic millis when the last chunk landed, for the same staleness rule
    //! the state line uses.
    var planAtMs = null;

    hidden var mRecentIds = [];

    function initialize() {
    }

    //! True until the first `state` message lands.
    function isWaiting() {
        return receivedAtMs == null;
    }

    //! Seconds since the last `state`, or null if there has not been one.
    //!
    //! `System.getTimer()` wraps around roughly every 25 days; a wrap reads as
    //! age 0, which errs toward "fresh" only for a watch that has been awake
    //! that long without a message, and self-corrects on the next one.
    function ageS() {
        if (receivedAtMs == null) {
            return null;
        }
        var elapsed = System.getTimer() - receivedAtMs;
        if (elapsed < 0) {
            return 0;
        }
        return elapsed / 1000;
    }

    //! Whether what is on screen should be greyed out.
    function isStale() {
        var age = ageS();
        return age != null && age > STALE_AFTER_S;
    }

    //! "4 min ago" / "2 h ago" - only used once stale, so seconds never matter.
    function ageText() {
        var age = ageS();
        if (age == null) {
            return "";
        }
        var minutes = age / 60;
        if (minutes < 60) {
            return minutes.toString() + " min ago";
        }
        return (minutes / 60).toString() + " h ago";
    }

    //! Applies a `state` message. Returns true if anything changed.
    function applyState(data) {
        live = Protocol.bool(data, "live", false);
        day = Protocol.str(data, "day");
        if (day != null) {
            day = Protocol.sanitise(day, 16);
        }
        var next = Protocol.dict(data, "next");
        if (next == null) {
            nextTitle = null;
            nextAt = null;
            nextDistM = null;
        } else {
            var title = Protocol.str(next, "title");
            nextTitle = (title == null) ? null : Protocol.sanitise(title, Protocol.MAX_LINE);
            nextAt = Protocol.str(next, "at");
            // A distance the phone did not send stays absent; it is never
            // derived from anything on the watch.
            nextDistM = Protocol.num(next, "dist");
            if (nextDistM != null && nextDistM < 0) {
                nextDistM = null;
            }
        }
        stateTs = Protocol.num(data, "ts");
        receivedAtMs = System.getTimer();
        return true;
    }

    //! Applies an `alert`. Returns true if it is new and should be shown and
    //! buzzed; false for a repeat, which is acknowledged again but not shown.
    function applyAlert(data) {
        var id = Protocol.str(data, "id");
        var text = Protocol.str(data, "text");
        if (id == null || text == null) {
            return false;
        }
        if (isRecent(id)) {
            return false;
        }
        remember(id);
        alertId = id;
        alertKind = Protocol.str(data, "kind");
        alertText = Protocol.sanitise(text, Protocol.MAX_LINE);
        return true;
    }

    //! Applies a `plan` chunk. Returns true when anything was stored.
    //!
    //! `i` is the index of the first step in this message, so a chunk starting
    //! at 0 begins a new plan and discards whatever was held. Out-of-order or
    //! repeated chunks are placed by index rather than appended, so a re-sent
    //! chunk overwrites rather than duplicating.
    function applyPlan(data) {
        var from = Protocol.num(data, "i");
        var total = Protocol.num(data, "tot");
        var steps = Protocol.list(data, "steps");
        if (from == null || total == null || from < 0 || total < 0) {
            return false;
        }

        if (from == 0) {
            planSteps = [];
            for (var i = 0; i < total && i < MAX_STEPS; i++) {
                planSteps.add(null);
            }
        }
        // A chunk arriving before its plan started (the `i == 0` message was
        // lost) still needs somewhere to go.
        while (planSteps.size() < total && planSteps.size() < MAX_STEPS) {
            planSteps.add(null);
        }

        planTotal = total;
        var day = Protocol.str(data, "day");
        if (day != null) {
            planDay = Protocol.sanitise(day, 16);
        }
        planAtMs = System.getTimer();

        if (steps == null) {
            return true;
        }
        for (var i = 0; i < steps.size(); i++) {
            var raw = steps[i];
            if (!(raw instanceof Lang.Dictionary)) {
                continue;
            }
            var text = Protocol.str(raw, "x");
            if (text == null) {
                continue;
            }
            var slot = from + i;
            if (slot < 0 || slot >= planSteps.size()) {
                continue;
            }
            planSteps[slot] = {
                "n" => Protocol.num(raw, "n") != null ? Protocol.num(raw, "n") : (slot + 1),
                "at" => Protocol.str(raw, "at"),
                "x" => Protocol.sanitise(text, MAX_STEP_CHARS),
                "m" => Protocol.str(raw, "m")
            };
        }
        return true;
    }

    //! Whether a usable plan has arrived.
    function hasPlan() {
        return planTotal > 0 && filledSteps() > 0;
    }

    //! How many steps actually have content, which may be fewer than
    //! [planTotal] while chunks are still arriving.
    function filledSteps() {
        var n = 0;
        for (var i = 0; i < planSteps.size(); i++) {
            if (planSteps[i] != null) { n++; }
        }
        return n;
    }

    //! The step the traveller is most likely to want: the first whose start
    //! time has not passed, or the last one once the day is over.
    //!
    //! Times are compared as text because they are already `HH:MM` on a 24 hour
    //! clock, which sorts lexicographically. That avoids carrying a timezone
    //! database onto the watch just to know which step is next.
    function currentStepIndex() {
        if (planSteps.size() == 0) {
            return 0;
        }
        var now = clockText();
        for (var i = 0; i < planSteps.size(); i++) {
            var step = planSteps[i];
            if (step == null) {
                continue;
            }
            var at = step["at"];
            if (at == null || at.length() < 5) {
                continue;
            }
            // First step that has not started yet.
            if (at.compareTo(now) >= 0) {
                return i;
            }
        }
        return planSteps.size() - 1;
    }

    //! The watch's own clock as "HH:MM", to compare against step times.
    hidden function clockText() {
        var t = System.getClockTime();
        return pad(t.hour) + ":" + pad(t.min);
    }

    hidden function pad(v) {
        return (v < 10) ? "0" + v.toString() : v.toString();
    }

    //! The step at `index`, or null if that chunk has not landed.
    function stepAt(index) {
        if (index < 0 || index >= planSteps.size()) {
            return null;
        }
        return planSteps[index];
    }

    function clearPlan() {
        planSteps = [];
        planTotal = 0;
        planDay = null;
        planAtMs = null;
    }

    //! Applies a `sosAck`. Returns true when the status is one we know.
    function applySosAck(data) {
        var status = Protocol.str(data, "status");
        if (status == null) {
            return false;
        }
        if (!(status.equals("countdown") || status.equals("cancelled") ||
              status.equals("sent") || status.equals("prepared") ||
              status.equals("failed"))) {
            return false;
        }
        sosStatus = status;
        var detail = Protocol.str(data, "detail");
        sosDetail = (detail == null) ? null : Protocol.sanitise(detail, Protocol.MAX_LINE);
        sosSecondsLeft = Protocol.num(data, "secondsLeft");
        return true;
    }

    //! Whether an SOS is still in its cancel window.
    function sosIsCounting() {
        return sosStatus != null && sosStatus.equals("countdown");
    }

    function clearSos() {
        sosStatus = null;
        sosDetail = null;
        sosSecondsLeft = null;
    }

    function clearAlert() {
        alertId = null;
        alertKind = null;
        alertText = null;
    }

    hidden function isRecent(id) {
        for (var i = 0; i < mRecentIds.size(); i++) {
            if (mRecentIds[i].equals(id)) {
                return true;
            }
        }
        return false;
    }

    hidden function remember(id) {
        mRecentIds.add(id);
        if (mRecentIds.size() > RECENT_ALERTS) {
            mRecentIds = mRecentIds.slice(mRecentIds.size() - RECENT_ALERTS, null);
        }
    }

    //! "1.2 km" / "420 m" - metric only; the fr965 setting is read by the view.
    static function distanceText(metres, statuteUnits) {
        if (metres == null) {
            return null;
        }
        if (statuteUnits) {
            var feet = metres * 3.28084;
            if (feet < 1000) {
                return feet.toNumber().toString() + " ft";
            }
            return (feet / 5280.0).format("%.1f") + " mi";
        }
        if (metres < 1000) {
            return metres.toString() + " m";
        }
        return (metres / 1000.0).format("%.1f") + " km";
    }
}
