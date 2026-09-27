import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Timer;
import Toybox.Time;

//! The SOS screen: hold for three seconds, then watch the phone report what it
//! actually did.
//!
//! The progress ring exists so a three-second hold is legible: the traveller can
//! see how much longer, and letting go before the end visibly abandons it.
//! Nothing is transmitted until the ring closes.
//!
//! After that, every line on this screen comes from a `sosAck` the phone sent.
//! The watch never says "sent" on its own - it cannot know, and guessing here is
//! the one mistake that would matter.
class SosView extends WatchUi.View {

    //! How long the button must be held.
    static const HOLD_MS = 3000;

    //! Ring refresh; 50 ms is smooth and cheap enough on an AMOLED.
    hidden const FRAME_MS = 50;

    hidden var mTimer = null;
    hidden var mHeldMs = 0;
    hidden var mHolding = false;
    hidden var mArmed = false;
    hidden var mLastTickAt = 0;

    function initialize() {
        View.initialize();
    }

    function onHide() {
        stopTimer();
    }

    //! The button went down.
    function beginHold() {
        if (mArmed) {
            return;
        }
        mHolding = true;
        mHeldMs = 0;
        mLastTickAt = 0;
        if (mTimer == null) {
            mTimer = new Timer.Timer();
            mTimer.start(method(:onFrame), FRAME_MS, true);
        }
        WatchUi.requestUpdate();
    }

    //! The button came up. Anything short of [HOLD_MS] is abandoned.
    function endHold() {
        if (!mHolding) {
            return;
        }
        mHolding = false;
        mHeldMs = 0;
        stopTimer();
        WatchUi.requestUpdate();
    }

    function onFrame() as Void {
        if (!mHolding) {
            return;
        }
        mHeldMs += FRAME_MS;
        // One tick per second of the hold, so the press is felt as well as seen.
        if (mHeldMs - mLastTickAt >= 1000) {
            mLastTickAt = mHeldMs;
            Buzz.tick();
        }
        if (mHeldMs >= HOLD_MS) {
            mHolding = false;
            stopTimer();
            fire();
        }
        WatchUi.requestUpdate();
    }

    //! The hold completed: tell the phone, and say only that we told it.
    hidden function fire() {
        mArmed = true;
        Buzz.forSos();
        var now = Time.now().value();
        app().transmit(Protocol.sos(now));
        WatchUi.requestUpdate();
    }

    //! BACK during the phone's countdown cancels instead of leaving.
    //! Returns true when it handled the press.
    function cancelIfCounting() {
        var state = UrbanPulseApp.state;
        if (state != null && state.sosIsCounting()) {
            app().transmit(Protocol.sosCancel());
            return true;
        }
        return false;
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var state = UrbanPulseApp.state;
        var hasAck = state != null && state.sosStatus != null;

        if (hasAck) {
            drawAck(dc, cx, h, state);
            return;
        }
        if (mArmed) {
            // Transmitted, nothing back yet. This is the honest wording: the
            // message left the watch; what the phone did with it is unknown.
            drawRing(dc, cx, cy, w, 1.0, Graphics.COLOR_RED);
            centre(dc, cx, h, Graphics.COLOR_WHITE, "Sent to phone", "waiting for the phone");
            return;
        }

        var progress = mHolding ? (mHeldMs * 1.0 / HOLD_MS) : 0.0;
        if (progress > 1.0) {
            progress = 1.0;
        }
        drawRing(dc, cx, cy, w, progress, Graphics.COLOR_RED);

        if (mHolding) {
            var left = (HOLD_MS - mHeldMs + 999) / 1000;
            centre(dc, cx, h, Graphics.COLOR_RED, "Keep holding", left.toString() + " s");
        } else {
            centre(dc, cx, h, Graphics.COLOR_WHITE, "SOS", "hold START 3 s");
        }
    }

    //! The ring: a full grey track with `progress` of it drawn in `colour`.
    hidden function drawRing(dc, cx, cy, w, progress, colour) {
        var radius = w * 0.44;
        var pen = w * 0.045;
        dc.setPenWidth(pen);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);

        if (progress <= 0.0) {
            return;
        }
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        // Degrees, counter-clockwise from 3 o'clock; start at 12 and sweep right.
        var sweep = (360 * progress).toNumber();
        if (sweep >= 360) {
            dc.drawCircle(cx, cy, radius);
            return;
        }
        if (sweep < 1) {
            sweep = 1;
        }
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, 90 - sweep);
    }

    hidden function centre(dc, cx, h, colour, title, subtitle) {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.38, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.56, Graphics.FONT_XTINY, subtitle, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! What the phone said, and nothing more.
    hidden function drawAck(dc, cx, h, state) {
        var status = state.sosStatus;
        var colour = Graphics.COLOR_WHITE;
        var ring = 1.0;
        if (status.equals("countdown")) {
            colour = Graphics.COLOR_RED;
            var left = state.sosSecondsLeft;
            // The ring empties as the cancel window closes.
            ring = (left == null) ? 1.0 : (left * 1.0 / 10.0);
            if (ring > 1.0) { ring = 1.0; }
            if (ring < 0.0) { ring = 0.0; }
        } else if (status.equals("sent")) {
            colour = Graphics.COLOR_GREEN;
        } else if (status.equals("prepared")) {
            colour = Graphics.COLOR_YELLOW;
        } else if (status.equals("failed")) {
            colour = Graphics.COLOR_RED;
        } else if (status.equals("cancelled")) {
            colour = Graphics.COLOR_LT_GRAY;
        }

        drawRing(dc, cx, dc.getHeight() / 2, dc.getWidth(), ring, colour);

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.34, Graphics.FONT_MEDIUM, headline(state),
                    Graphics.TEXT_JUSTIFY_CENTER);

        var detail = state.sosDetail;
        if (detail != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.55, Graphics.FONT_XTINY,
                        Protocol.truncate(detail, 34), Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var hint = status.equals("countdown") ? "BACK to cancel" : "BACK to close";
        dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function headline(state) {
        var status = state.sosStatus;
        if (status.equals("countdown")) {
            var left = state.sosSecondsLeft;
            return (left == null) ? "Sending" : left.toString() + " s";
        }
        if (status.equals("cancelled")) {
            return "Cancelled";
        }
        if (status.equals("sent")) {
            return "Sent";
        }
        if (status.equals("prepared")) {
            return "Ready";
        }
        return "Failed";
    }

    //! The one-line version for the Home footer.
    static function statusText(state) {
        var status = state.sosStatus;
        if (status == null) {
            return "";
        }
        if (status.equals("countdown")) {
            var left = state.sosSecondsLeft;
            return (left == null) ? "SOS sending" : "SOS in " + left.toString() + " s";
        }
        if (status.equals("cancelled")) {
            return "SOS cancelled";
        }
        if (status.equals("sent")) {
            return "SOS sent";
        }
        if (status.equals("prepared")) {
            // Deliberately not "sent": the phone opened a composer.
            return "SOS ready on phone";
        }
        return "SOS failed";
    }

    hidden function stopTimer() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
    }
}
