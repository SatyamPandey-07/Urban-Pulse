import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Graphics;

//! The whole trip as one scrolling list, grouped by day.
//!
//! Scrolling runs straight through: the steps of the first day, then a heading
//! for the next day, then its steps, and so on. Reaching the end of today
//! continues into tomorrow rather than stopping, which is what makes the list a
//! trip rather than a page.
//!
//! Pagination is by measurement, not by a fixed rows-per-page. Rows are drawn
//! until the next one would not fit the *chord* of the round screen at that
//! height (see [Layout]), and where the page broke becomes the start of the next
//! one. So a day of short steps fits more rows than a day of long ones, and
//! nothing is ever half-drawn at the bottom edge.
class PlanView extends WatchUi.View {

    //! Where each page starts, as an index into the step list. Grown as the
    //! traveller scrolls, because where a page ends is only known once drawn.
    hidden var mPageStarts = [0];
    hidden var mPage = 0;

    //! The index after the last row drawn on the current page, so [move] knows
    //! whether there is anything below.
    hidden var mNextStart = 0;

    function initialize(startStep) {
        View.initialize();
        if (startStep != null && startStep > 0) {
            // Open near the step that is happening now: begin the first page
            // there rather than at the top of the trip.
            mPageStarts = [startStep];
        }
    }

    //! Moves a page down (+1) or up (-1). Returns true if anything changed.
    function move(delta) {
        var state = UrbanPulseApp.state;
        if (state == null || state.planSteps.size() == 0) {
            return false;
        }
        if (delta > 0) {
            // Only page down if the last draw actually left rows below.
            if (mNextStart >= state.planSteps.size()) {
                return false;
            }
            if (mPage + 1 >= mPageStarts.size()) {
                mPageStarts.add(mNextStart);
            }
            mPage++;
        } else {
            if (mPage == 0) {
                return false;
            }
            mPage--;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var state = UrbanPulseApp.state;
        if (state == null || !state.hasPlan()) {
            drawEmpty(dc, h);
            return;
        }

        var total = state.planSteps.size();
        var start = mPageStarts[mPage];
        if (start >= total) {
            start = 0;
            mPage = 0;
            mPageStarts = [0];
        }

        // Rows run between the top and bottom hints; both are reserved first so
        // a row is never drawn under them.
        var top = h * 0.115;
        var bottom = h * 0.80;

        var y = top;
        var index = start;
        while (index < total && y < bottom) {
            var used = drawRow(dc, y, bottom, state, index);
            if (used <= 0) {
                // The next row did not fit: the page ends here.
                break;
            }
            y += used;
            index++;
        }
        // A page that could fit nothing at all must still advance, or scrolling
        // would stall on an over-long step.
        if (index == start && start < total) {
            index = start + 1;
        }
        mNextStart = index;

        drawScrollbar(dc, w, h, start, index, total);
        drawFooter(dc, h, state, index, total);
    }

    //! Draws one row (a day heading, if it starts one, plus the step) and
    //! returns the height used, or 0 when it would not fit above `bottom`.
    hidden function drawRow(dc, y, bottom, state, index) {
        var step = state.stepAt(index);
        var used = 0;

        // --- the day heading ----------------------------------------------
        if (state.startsDay(index)) {
            var headFont = Graphics.FONT_XTINY;
            var headH = dc.getFontHeight(headFont);
            if (y + headH > bottom) {
                return 0;
            }
            var label = state.dayOf(index);
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            // A rule either side of the label, drawn to the chord so it never
            // reaches past the curve.
            var chord = Layout.chordWidth(dc, y + headH / 2);
            var cx = dc.getWidth() / 2;
            var textW = dc.getTextWidthInPixels(label, headFont);
            var ruleY = y + headH / 2;
            dc.setPenWidth(1);
            if (chord > textW + 20) {
                dc.drawLine(cx - chord / 2, ruleY, cx - textW / 2 - 6, ruleY);
                dc.drawLine(cx + textW / 2 + 6, ruleY, cx + chord / 2, ruleY);
            }
            dc.drawText(cx, y, headFont, label, Graphics.TEXT_JUSTIFY_CENTER);
            y += headH;
            used += headH;
        }

        if (step == null) {
            // A chunk that has not landed. Say so rather than leave a gap.
            var pendingH = dc.getFontHeight(Graphics.FONT_XTINY);
            if (y + pendingH > bottom) {
                return (used > 0) ? used : 0;
            }
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, y, Graphics.FONT_XTINY, "loading...",
                        Graphics.TEXT_JUSTIFY_CENTER);
            return used + pendingH;
        }

        // --- the step ------------------------------------------------------
        // "3) 09:30  Take the train from Panvel to CST", wrapped to fit the
        // chord, at the largest size that keeps it to two lines.
        var body = step["n"].toString() + ") " + step["x"];
        var when = step["at"];

        var font = Graphics.FONT_XTINY;
        var lineH = dc.getFontHeight(font);
        var lines = Layout.wrap(dc, body, font, Layout.chordWidth(dc, y + lineH));
        var wanted = lines.size();
        if (wanted > 3) { wanted = 3; }
        var timeH = (when == null) ? 0 : dc.getFontHeight(Graphics.FONT_XTINY);
        var needed = wanted * lineH + timeH * 0;

        if (y + needed > bottom) {
            return (used > 0) ? used : 0;
        }

        // The time leads the row in the mode's colour, so the kind of step and
        // when it happens read before the words do.
        if (when != null) {
            dc.setColor(modeColour(step["m"]), Graphics.COLOR_TRANSPARENT);
            var label = modeLabel(step["m"]);
            var head = (label.length() > 0) ? when + "  " + label : when;
            dc.drawText(dc.getWidth() / 2, y, Graphics.FONT_XTINY, head,
                        Graphics.TEXT_JUSTIFY_CENTER);
            y += lineH;
            used += lineH;
            if (y + wanted * lineH > bottom) {
                return used;
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < wanted; i++) {
            dc.drawText(dc.getWidth() / 2, y + i * lineH, font, lines[i],
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
        used += wanted * lineH;

        // A little air between steps, so rows do not run together.
        return used + lineH * 0.25;
    }

    hidden function drawEmpty(dc, h) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.40, "No plan yet", Layout.BODY_FONTS);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        Layout.drawFitted(dc, h * 0.54, "Open Urban Pulse and", [Graphics.FONT_XTINY]);
        Layout.drawFitted(dc, h * 0.63, "send the plan", [Graphics.FONT_XTINY]);
    }

    //! A bar down the right-hand side showing how far through the trip this
    //! page is - the round-screen equivalent of a scrollbar.
    hidden function drawScrollbar(dc, w, h, start, end, total) {
        if (total <= 0) {
            return;
        }
        var x = w * 0.955;
        var top = h * 0.22;
        var height = h * 0.56;

        dc.setPenWidth(w * 0.012);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, top, x, top + height);

        var from = top + height * (start * 1.0 / total);
        var to = top + height * (end * 1.0 / total);
        if (to - from < height * 0.06) {
            to = from + height * 0.06;
        }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, from, x, to);
    }

    //! The bottom line: how far through, and which key does what.
    hidden function drawFooter(dc, h, state, end, total) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var more = (end < total);
        var hint;
        if (more && mPage > 0) {
            hint = "UP / DOWN";
        } else if (more) {
            hint = "DOWN for more";
        } else if (mPage > 0) {
            hint = "UP to go back";
        } else {
            hint = "BACK";
        }
        Layout.drawFitted(dc, h * 0.835, hint, [Graphics.FONT_XTINY]);
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
