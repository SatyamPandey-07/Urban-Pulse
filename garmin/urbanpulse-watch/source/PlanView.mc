import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Graphics;

//! The day's plan, one step to a page.
//!
//! A watch screen cannot hold a day, and a list of twelve four-word rows is not
//! readable on a wrist at walking pace. So each step gets the whole screen: its
//! number, when it starts, how it is travelled, and what to do, at the largest
//! font that fits. DOWN moves to the next step, UP to the previous.
//!
//! Position is shown twice, deliberately: as "3/12" for precision, and as an arc
//! around the bezel for a glance. The arc is the part that uses a round screen
//! for something other than losing corners.
//!
//! Every measurement comes from [Layout], so nothing here assumes 454 px.
class PlanView extends WatchUi.View {

    //! Which step is on screen, 0-based.
    hidden var mIndex = 0;

    function initialize(index) {
        View.initialize();
        mIndex = (index == null) ? 0 : index;
    }

    function index() {
        return mIndex;
    }

    //! Moves by `delta` steps, stopping at the ends rather than wrapping: a plan
    //! has a beginning and an end, and silently looping hides which you are at.
    //! Returns true if the position changed.
    function move(delta) {
        var state = UrbanPulseApp.state;
        if (state == null) {
            return false;
        }
        var count = state.planSteps.size();
        if (count <= 0) {
            return false;
        }
        var next = mIndex + delta;
        if (next < 0) { next = 0; }
        if (next >= count) { next = count - 1; }
        if (next == mIndex) {
            return false;
        }
        mIndex = next;
        WatchUi.requestUpdate();
        return true;
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var state = UrbanPulseApp.state;
        if (state == null || !state.hasPlan()) {
            drawEmpty(dc, cx, h);
            return;
        }

        var total = state.planSteps.size();
        drawProgressArc(dc, cx, h / 2, w, mIndex, total);

        var step = state.stepAt(mIndex);
        if (step == null) {
            // This chunk has not arrived. Say so rather than draw a blank page.
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            Layout.drawFitted(dc, h * 0.44, "Step " + (mIndex + 1).toString(), Layout.BODY_FONTS);
            Layout.drawFitted(dc, h * 0.56, "still loading", Layout.BODY_FONTS);
            drawFooter(dc, cx, h, total);
            return;
        }

        // --- top: the day, and where we are in it -------------------------
        var heading = (mIndex + 1).toString() + " / " + total.toString();
        if (state.planDay != null) {
            heading = state.planDay + "   " + heading;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.135, heading, [Graphics.FONT_XTINY]);

        // --- the mode and the time ----------------------------------------
        var mode = step["m"];
        var at = step["at"];
        var line = modeLabel(mode);
        if (at != null) {
            line = (line.length() > 0) ? line + "  " + at : at;
        }
        dc.setColor(modeColour(mode), Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.245, line, [Graphics.FONT_TINY, Graphics.FONT_XTINY]);

        // --- the step itself ----------------------------------------------
        // The number is part of the sentence ("3) Take the train ..."), so it is
        // drawn with the text and wraps with it.
        var body = step["n"].toString() + ") " + step["x"];
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        Layout.drawWrapped(dc, h * 0.375, body, Layout.BODY_FONTS, 4);

        drawFooter(dc, cx, h, total);
    }

    hidden function drawEmpty(dc, cx, h) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.40, "No plan yet", Layout.BODY_FONTS);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.54, "Open Urban Pulse and", [Graphics.FONT_XTINY]);
        Layout.drawFitted(dc, h * 0.63, "start Live Mode", [Graphics.FONT_XTINY]);
    }

    //! The hint, and only while it is useful.
    hidden function drawFooter(dc, cx, h, total) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var hint = "BACK";
        if (total > 1) {
            if (mIndex == 0) {
                hint = "DOWN for next";
            } else if (mIndex == total - 1) {
                hint = "UP to go back";
            } else {
                hint = "UP / DOWN";
            }
        }
        Layout.drawFitted(dc, h * 0.845, hint, [Graphics.FONT_XTINY]);
    }

    //! An arc around the bezel: grey for the whole day, bright for how far in.
    hidden function drawProgressArc(dc, cx, cy, w, index, total) {
        if (total <= 1) {
            return;
        }
        var radius = w * 0.47;
        dc.setPenWidth(w * 0.018);

        // The track runs from 10 o'clock round the top to 2 o'clock.
        var startDeg = 150;
        var sweepDeg = 240;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, startDeg, startDeg - sweepDeg);

        var done = ((index + 1) * 1.0 / total);
        var progressed = (sweepDeg * done).toNumber();
        if (progressed < 2) { progressed = 2; }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, startDeg, startDeg - progressed);
    }

    //! Short, upper-case, and ASCII - the watch has one font.
    static function modeLabel(mode) {
        if (mode == null) { return ""; }
        if (mode.equals("train")) { return "TRAIN"; }
        if (mode.equals("bus")) { return "BUS"; }
        if (mode.equals("walk")) { return "WALK"; }
        if (mode.equals("cab")) { return "CAB"; }
        if (mode.equals("flight")) { return "FLIGHT"; }
        if (mode.equals("visit")) { return "VISIT"; }
        if (mode.equals("meal")) { return "MEAL"; }
        if (mode.equals("hotel")) { return "STAY"; }
        return "";
    }

    //! Colour per mode, so the kind of step reads before the words do.
    static function modeColour(mode) {
        if (mode == null) { return Graphics.COLOR_LT_GRAY; }
        if (mode.equals("train") || mode.equals("bus")) { return Graphics.COLOR_BLUE; }
        if (mode.equals("walk")) { return Graphics.COLOR_GREEN; }
        if (mode.equals("cab") || mode.equals("flight")) { return Graphics.COLOR_ORANGE; }
        if (mode.equals("meal")) { return Graphics.COLOR_YELLOW; }
        if (mode.equals("visit")) { return Graphics.COLOR_PINK; }
        if (mode.equals("hotel")) { return Graphics.COLOR_PURPLE; }
        return Graphics.COLOR_LT_GRAY;
    }
}
