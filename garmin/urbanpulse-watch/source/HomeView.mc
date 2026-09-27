import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Graphics;

//! The resting screen: what the phone last said, and how much to trust it.
//!
//! Every coordinate is a fraction of `dc.getWidth()` / `dc.getHeight()`, and the
//! text is centred within an inset that keeps it off a round bezel, so adding a
//! product to the manifest needs no change here.
class HomeView extends WatchUi.View {

    //! Fraction of the radius kept clear of the curved edge.
    hidden const INSET = 0.13;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        // Coming back from the alert or SOS screen: pick up whatever arrived.
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var state = UrbanPulseApp.state;
        if (state == null || state.isWaiting()) {
            drawWaiting(dc, cx, h);
            return;
        }

        var stale = state.isStale();
        // Greyed when stale: still shown, plainly not current.
        var titleColour = stale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_WHITE;
        var metaColour = stale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;

        // --- top: the trip status line -----------------------------------
        var status = statusLine(state, stale);
        dc.setColor(metaColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.17, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_CENTER);

        // --- the phone-connected dot -------------------------------------
        drawLinkDot(dc, w, h, state);

        // --- middle: the next stop ---------------------------------------
        if (state.nextTitle == null) {
            dc.setColor(titleColour, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.42, Graphics.FONT_SMALL,
                        state.live ? "No next stop" : "Live Mode off",
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(titleColour, Graphics.COLOR_TRANSPARENT);
            // FONT_MEDIUM wraps nothing, so the title is drawn over up to two
            // lines split on a space rather than clipped at the bezel.
            drawWrapped(dc, cx, h * 0.33, w * (1.0 - 2 * INSET),
                        Graphics.FONT_MEDIUM, state.nextTitle);

            // --- time, and distance if the phone sent one ----------------
            var line = (state.nextAt == null) ? "" : state.nextAt;
            var dist = LinkState.distanceText(state.nextDistM, statuteUnits());
            if (dist != null) {
                line = line.length() > 0 ? line + "  -  " + dist : dist;
            }
            if (line.length() > 0) {
                dc.setColor(stale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_GREEN,
                            Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.60, Graphics.FONT_NUMBER_MILD, line,
                            Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        // --- bottom: the SOS state, or the hint ---------------------------
        drawFooter(dc, cx, h, state);
    }

    //! "Waiting for phone" - the state before anything has ever arrived. It is
    //! not an error, and it does not pretend to be a plan.
    hidden function drawWaiting(dc, cx, h) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.40, Graphics.FONT_SMALL, "Waiting for phone",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.54, Graphics.FONT_XTINY, "Open Urban Pulse",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.64, Graphics.FONT_XTINY, "and turn on Live Mode",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function statusLine(state, stale) {
        if (stale) {
            return state.ageText();
        }
        if (state.day != null) {
            return state.live ? state.day + " - live" : state.day;
        }
        return state.live ? "Live" : "Not live";
    }

    //! A small filled dot, top centre: green when the phone is talking to us,
    //! hollow grey when it is not.
    hidden function drawLinkDot(dc, w, h, state) {
        var r = w * 0.016;
        var y = h * 0.10;
        var connected = state.phoneConnected && !state.isStale();
        if (connected) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(w / 2, y, r);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawCircle(w / 2, y, r);
        }
    }

    hidden function drawFooter(dc, cx, h, state) {
        if (state.sosStatus != null) {
            var text = SosView.statusText(state);
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, text,
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.82, Graphics.FONT_XTINY, "Hold START for SOS",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draws `text` centred at `y`, over two lines if it does not fit `maxW`.
    hidden function drawWrapped(dc, cx, y, maxW, font, text) {
        if (dc.getTextWidthInPixels(text, font) <= maxW) {
            dc.drawText(cx, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var split = splitPoint(dc, text, font, maxW);
        if (split <= 0) {
            dc.drawText(cx, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var lineH = dc.getFontHeight(font);
        dc.drawText(cx, y - lineH * 0.15, font, text.substring(0, split),
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, y - lineH * 0.15 + lineH * 0.92, font,
                    text.substring(split + 1, text.length()),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Index of the space to break on: the last one whose prefix still fits.
    hidden function splitPoint(dc, text, font, maxW) {
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

    //! The traveller's own unit setting; the phone always sends metres.
    hidden function statuteUnits() {
        var settings = System.getDeviceSettings();
        if (settings == null || !(settings has :distanceUnits)) {
            return false;
        }
        return settings.distanceUnits == System.UNIT_STATUTE;
    }
}
