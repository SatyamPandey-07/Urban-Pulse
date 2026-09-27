import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Timer;

//! One Live Mode update: its kind, its line of text, and a way out.
//!
//! The buzz has already happened by the time this is pushed (the app buzzes on
//! receipt, so a message that arrives while the watch is in a pocket is still
//! felt). This screen is the text.
class AlertView extends WatchUi.View {

    hidden const INSET = 0.13;

    //! Dismisses itself, so an alert never sits on screen over the next stop.
    hidden const AUTO_DISMISS_MS = 20000;

    hidden var mTimer = null;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        mTimer = new Timer.Timer();
        mTimer.start(method(:onTimeout), AUTO_DISMISS_MS, false);
    }

    function onHide() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
    }

    function onTimeout() as Void {
        dismiss();
    }

    //! Clears the alert and goes back to Home.
    function dismiss() as Void {
        var state = UrbanPulseApp.state;
        if (state != null) {
            state.clearAlert();
        }
        try {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        } catch (e) {
            // Already popped.
        }
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        var state = UrbanPulseApp.state;
        var kind = (state == null) ? null : state.alertKind;

        dc.setColor(Graphics.COLOR_TRANSPARENT, colourFor(kind));
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.18, Graphics.FONT_XTINY, labelFor(kind),
                    Graphics.TEXT_JUSTIFY_CENTER);

        var text = (state == null || state.alertText == null) ? "" : state.alertText;
        drawParagraph(dc, cx, h * 0.34, w * (1.0 - 2 * INSET), Graphics.FONT_SMALL, text);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.82, Graphics.FONT_XTINY, "BACK to dismiss",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! A colour per kind, so the alert is readable before the text is.
    static function colourFor(kind) {
        if (kind == null) {
            return Graphics.COLOR_DK_BLUE;
        }
        if (kind.equals(Protocol.KIND_LEAVE)) {
            return Graphics.COLOR_DK_BLUE;
        }
        if (kind.equals(Protocol.KIND_ARRIVED)) {
            return Graphics.COLOR_DK_GREEN;
        }
        if (kind.equals(Protocol.KIND_LATE)) {
            return Graphics.COLOR_DK_RED;
        }
        if (kind.equals(Protocol.KIND_MEAL)) {
            return Graphics.COLOR_ORANGE;
        }
        if (kind.equals(Protocol.KIND_RAIN)) {
            return Graphics.COLOR_DK_GRAY;
        }
        return Graphics.COLOR_DK_BLUE;
    }

    static function labelFor(kind) {
        if (kind == null) {
            return "UPDATE";
        }
        if (kind.equals(Protocol.KIND_LEAVE)) {
            return "LEAVE NOW";
        }
        if (kind.equals(Protocol.KIND_ARRIVED)) {
            return "ARRIVED";
        }
        if (kind.equals(Protocol.KIND_LATE)) {
            return "RUNNING BEHIND";
        }
        if (kind.equals(Protocol.KIND_MEAL)) {
            return "MEAL";
        }
        if (kind.equals(Protocol.KIND_RAIN)) {
            return "RAIN";
        }
        return "UPDATE";
    }

    //! Draws `text` over as many lines as it needs, breaking on spaces.
    hidden function drawParagraph(dc, cx, top, maxW, font, text) {
        if (text.length() == 0) {
            return;
        }
        var lineH = dc.getFontHeight(font);
        var y = top;
        var rest = text;
        // Four lines is all that fits between the label and the hint.
        for (var line = 0; line < 4 && rest.length() > 0; line++) {
            if (dc.getTextWidthInPixels(rest, font) <= maxW) {
                dc.drawText(cx, y, font, rest, Graphics.TEXT_JUSTIFY_CENTER);
                return;
            }
            var cut = lastFittingSpace(dc, rest, font, maxW);
            if (cut <= 0) {
                dc.drawText(cx, y, font, rest, Graphics.TEXT_JUSTIFY_CENTER);
                return;
            }
            dc.drawText(cx, y, font, rest.substring(0, cut), Graphics.TEXT_JUSTIFY_CENTER);
            rest = rest.substring(cut + 1, rest.length());
            y += lineH * 0.92;
        }
    }

    hidden function lastFittingSpace(dc, text, font, maxW) {
        var chars = text.toCharArray();
        var best = -1;
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i].toNumber() != 0x20) {
                continue;
            }
            if (dc.getTextWidthInPixels(text.substring(0, i), font) <= maxW) {
                best = i;
            } else {
                break;
            }
        }
        return best;
    }
}
