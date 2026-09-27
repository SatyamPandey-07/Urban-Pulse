import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Graphics;

//! The resting screen: what the phone last said, and how much to trust it.
//!
//! Laid out through [Layout], so every line is measured against the *chord* of
//! the round screen at its own height rather than the full width. That is what
//! stops a long place name running off the curve, and it is why the title font
//! is chosen per render instead of fixed: "CST" gets a big one, "Chhatrapati
//! Shivaji Maharaj Terminus" gets a smaller one and two lines, and neither
//! overflows.
class HomeView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onShow() {
        // Coming back from the alert, plan or SOS screen: pick up what arrived.
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var state = UrbanPulseApp.state;
        if (state == null || state.isWaiting()) {
            drawWaiting(dc, h);
            return;
        }

        var stale = state.isStale();
        // Greyed when stale: still shown, plainly not current.
        var titleColour = stale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_WHITE;
        var metaColour = stale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;

        drawLinkDot(dc, w, h, state);

        // --- top: the trip status line ------------------------------------
        dc.setColor(metaColour, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.155, statusLine(state, stale), [Graphics.FONT_XTINY]);

        // --- middle: what is next -----------------------------------------
        if (state.nextTitle == null) {
            dc.setColor(titleColour, Graphics.COLOR_TRANSPARENT);
            Layout.drawFitted(dc, h * 0.44,
                              state.live ? "No next stop" : "Live Mode off",
                              Layout.BODY_FONTS);
        } else {
            dc.setColor(titleColour, Graphics.COLOR_TRANSPARENT);
            // Two lines at the largest size that fits; the font shrinks before
            // the words are ever cut.
            var below = Layout.drawWrapped(dc, h * 0.30, state.nextTitle,
                                           Layout.TITLE_FONTS, 2);

            // --- when, and how far, on one line where it fits --------------
            var when = (state.nextAt == null) ? "" : state.nextAt;
            var dist = LinkState.distanceText(state.nextDistM, statuteUnits());
            var y = below + h * 0.03;
            dc.setColor(stale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_GREEN,
                        Graphics.COLOR_TRANSPARENT);
            if (when.length() > 0 && dist != null) {
                var joined = when + "   " + dist;
                // Only join them if the pair fits; otherwise the time leads and
                // the distance goes underneath rather than being squeezed.
                if (dc.getTextWidthInPixels(joined, Graphics.FONT_TINY) <= Layout.chordWidth(dc, y)) {
                    Layout.drawFitted(dc, y, joined, Layout.NUMBER_FONTS);
                } else {
                    var after = Layout.drawFitted(dc, y, when, Layout.NUMBER_FONTS);
                    dc.setColor(metaColour, Graphics.COLOR_TRANSPARENT);
                    Layout.drawFitted(dc, after, dist, [Graphics.FONT_TINY, Graphics.FONT_XTINY]);
                }
            } else if (when.length() > 0) {
                Layout.drawFitted(dc, y, when, Layout.NUMBER_FONTS);
            } else if (dist != null) {
                Layout.drawFitted(dc, y, dist, Layout.NUMBER_FONTS);
            }
        }

        drawFooter(dc, h, state);
    }

    //! The state before anything has ever arrived. Not an error, and it does not
    //! pretend to be a plan.
    hidden function drawWaiting(dc, h) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.38, "Waiting for phone", Layout.BODY_FONTS);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.54, "Open Urban Pulse", [Graphics.FONT_XTINY]);
        Layout.drawFitted(dc, h * 0.63, "and turn on Live Mode", [Graphics.FONT_XTINY]);
    }

    hidden function statusLine(state, stale) {
        if (stale) {
            return state.ageText();
        }
        if (state.planDay != null) {
            return state.live ? state.planDay + " - live" : state.planDay;
        }
        if (state.day != null) {
            return state.live ? state.day + " - live" : state.day;
        }
        return state.live ? "Live" : "Not live";
    }

    //! A small dot, top centre: filled green when the phone is talking to us,
    //! hollow grey when it is not.
    hidden function drawLinkDot(dc, w, h, state) {
        var r = w * 0.016;
        var y = h * 0.095;
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

    //! The bottom line says whichever is more useful right now: a live SOS, the
    //! plan when there is one, or the SOS hint.
    hidden function drawFooter(dc, h, state) {
        if (state.sosStatus != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            Layout.drawFitted(dc, h * 0.80, SosView.statusText(state), [Graphics.FONT_XTINY]);
            return;
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        if (state.hasPlan()) {
            var steps = state.planSteps.size();
            var days = state.dayCount();
            var hint = "DOWN: " + steps.toString() + " steps";
            if (days > 1) {
                // Worth saying: the list runs past today into the rest of the trip.
                hint = "DOWN: " + days.toString() + " days, " + steps.toString() + " steps";
            }
            Layout.drawFitted(dc, h * 0.815, hint, [Graphics.FONT_XTINY]);
        } else {
            // The bottom band is the SOS tap target, so the words in it say so.
            Layout.drawFitted(dc, h * 0.825, "Tap here for SOS", [Graphics.FONT_XTINY]);
        }
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
