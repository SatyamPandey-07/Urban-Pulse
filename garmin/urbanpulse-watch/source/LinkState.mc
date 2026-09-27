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
