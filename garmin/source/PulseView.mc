//
// PulseView - everything that touches the screen.
//
// Three pages over one trip, in the order you need them: what is next, the
// whole day, then the trip. Not one coordinate is hard-coded to 454: every
// position comes from dc.getWidth() / dc.getHeight(), and each row is sized to
// the chord of the display circle at that row's outermost edge,
//
//     halfWidth = sqrt(r^2 - dy^2)
//
// so rows taper towards the top and bottom instead of being clipped by the
// bezel.
//
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// AMOLED: black pixels cost no power, so the UI is dark with bright glyphs.
const COL_BG      = 0x000000;
const COL_CARD    = 0x121B21;
const COL_CARD_HI = 0x10323F;
const COL_TEXT    = 0xE3ECF1;
const COL_DIM     = 0x7C9099;
const COL_ACCENT  = 0x45B7E7;
const COL_WARN    = 0xDEA34C;

// One colour per slot kind, used for the rail on each timeline row.
const COL_STAY    = 0x9A7BD0;
const COL_VISIT   = 0x45B7E7;
const COL_MEAL    = 0xDEA34C;
const COL_TRANSIT = 0x4FD1A5;
const COL_REST    = 0x5B6E77;

class PulseView extends WatchUi.View {

    static const PAGE_NEXT = 0;
    static const PAGE_DAY  = 1;
    static const PAGE_TRIP = 2;
    static const PAGES     = 3;

    // Timeline rows visible at once on a round face.
    static const ROWS = 4;

    private var _store as TripStore;

    private var _page as Number;
    private var _day as Number;                  // day being browsed on PAGE_DAY
    private var _scroll as Number;               // first visible timeline row
    private var _syncing as Boolean;
    private var _dayPinned as Boolean;           // user moved off "today" by hand
    private var _tick as Timer.Timer or Null;    // keeps the countdown honest

    private var _w as Number;
    private var _h as Number;
    private var _cx as Number;
    private var _cy as Number;
    private var _r as Number;

    function initialize(store as TripStore) {
        View.initialize();
        _store = store;
        _page = PAGE_NEXT;
        _day = 0;
        _scroll = 0;
        _syncing = false;
        _dayPinned = false;
        _tick = null;
        _w = 0;
        _h = 0;
        _cx = 0;
        _cy = 0;
        _r = 0;
    }

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        _r = _w / 2;
    }

    // ------------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------------

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COL_BG, COL_BG);
        dc.clear();

        var now = Time.now().value();

        if (!_store.hasTrip()) {
            drawEmpty(dc);
            return;
        }

        // Follow the clock across midnight unless the user is browsing.
        if (!_dayPinned) { _day = _store.dayIndexFor(now); }

        if (_page == PAGE_NEXT)     { drawNextUp(dc, now); }
        else if (_page == PAGE_DAY) { drawDay(dc, now); }
        else                        { drawTrip(dc, now); }

        drawDots(dc);
        if (_syncing) { drawSyncArc(dc); }
    }

    // ---- page 0: what happens next -----------------------------------

    private function drawNextUp(dc as Dc, now as Number) as Void {
        centred(dc, frac(0.105), Graphics.FONT_XTINY, COL_ACCENT,
                Fmt.clip(_store.destination().toUpper(), 22));

        var state = _store.state(now);
        var sub;
        if (state == :before)     { sub = "starts in " + Fmt.span(_store.tripStart() - now); }
        else if (state == :after) { sub = "trip complete"; }
        else                      { sub = "day " + (_day + 1).toString() + " of " + _store.dayCount().toString(); }
        centred(dc, frac(0.175), Graphics.FONT_XTINY, COL_DIM, sub);

        // Whatever is happening right now wins; otherwise the next thing.
        var here = _store.currentSlot(now);
        var isNow = here != null;
        var at = isNow ? here : _store.nextSlot(now);

        if (at == null) {
            centred(dc, frac(0.46), Graphics.FONT_MEDIUM, COL_TEXT,
                    state == :before ? "Not started" : "Nothing left");
            centred(dc, frac(0.57), Graphics.FONT_XTINY, COL_DIM, _store.dateRange());
            drawFooter(dc, now);
            return;
        }

        var slot = _store.slot(at[0] as Number, at[1] as Number);
        if (slot == null) { return; }

        centred(dc, frac(0.262), Graphics.FONT_XTINY, isNow ? COL_WARN : COL_ACCENT,
                isNow ? "NOW" : ((at[0] as Number) == _day ? "NEXT" : "TOMORROW"));

        centred(dc, frac(0.368), Graphics.FONT_NUMBER_MEDIUM, COL_TEXT,
                TripStore.text(slot, "hm", "--:--"));

        // The title gets two lines; the font shrinks before the text is cut.
        var title = TripStore.text(slot, "ti", "");
        var maxW = chord(frac(0.545) - _cy) * 2;
        var font = dc.getTextWidthInPixels(title, Graphics.FONT_MEDIUM) <= maxW
                 ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL;
        var lines = wrap(dc, title, font, maxW, 2);
        var lineH = dc.getFontHeight(font);
        var top = frac(0.50);
        for (var i = 0; i < lines.size(); i++) {
            centred(dc, top + (i * lineH), font, COL_TEXT, lines[i] as String);
        }

        var until = isNow ? (TripStore.count(slot, "z", now) - now)
                          : (TripStore.count(slot, "a", now) - now);
        centred(dc, frac(0.695), Graphics.FONT_XTINY,
                kindColour(TripStore.text(slot, "k", KIND_VISIT)),
                (isNow ? "ends in " : "in ") + Fmt.span(until));

        centred(dc, frac(0.775), Graphics.FONT_XTINY, COL_DIM, detailFor(slot));
        drawFooter(dc, now);
    }

    // Distance and bearing when the watch has a fix and the stop has a
    // coordinate; otherwise whatever else is worth a line.
    private function detailFor(slot as Dictionary) as String {
        var target = TripStore.position(slot);
        var fix = currentPosition();
        if (target != null && fix != null) {
            var metres = Fmt.metresBetween(fix[0] as Float, fix[1] as Float,
                                           target[0] as Float, target[1] as Float);
            var bearing = Fmt.bearingBetween(fix[0] as Float, fix[1] as Float,
                                             target[0] as Float, target[1] as Float);
            var metric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            return Fmt.distance(metres, metric) + "  " + Fmt.compass(bearing);
        }

        var flags = TripStore.text(slot, "fl", "");
        if (!flags.equals("")) { return Fmt.clip(flags, 26); }

        var cost = TripStore.count(slot, "c", 0);
        if (cost > 0) { return Fmt.money(cost); }

        var note = TripStore.text(slot, "no", "");
        return Fmt.clip(note, 30);
    }

    private function currentPosition() as Array or Null {
        if (!(Position has :getInfo)) { return null; }
        var info = Position.getInfo();
        if (info == null || info.position == null) { return null; }
        if (info.accuracy == null || info.accuracy == Position.QUALITY_NOT_AVAILABLE) { return null; }
        var deg = info.position.toDegrees();
        return [ (deg[0] as Double).toFloat(), (deg[1] as Double).toFloat() ];
    }

    // ---- page 1: the day, hour by hour -------------------------------

    private function drawDay(dc as Dc, now as Number) as Void {
        var day = _store.day(_day);
        var header = "DAY " + TripStore.count(day, "n", _day + 1).toString();
        var date = TripStore.text(day, "dt", "");
        if (!date.equals("")) { header += "  " + date.toUpper(); }
        centred(dc, frac(0.10), Graphics.FONT_XTINY, COL_ACCENT, Fmt.clip(header, 24));

        var weather = TripStore.text(day, "w", "");
        centred(dc, frac(0.165), Graphics.FONT_XTINY, COL_DIM, Fmt.clip(weather, 26));

        var list = _store.slots(_day);
        if (list.size() == 0) {
            centred(dc, _cy, Graphics.FONT_SMALL, COL_DIM, "Nothing planned");
            return;
        }

        clampScroll(list.size());
        var here = _store.currentSlot(now);
        var hereIndex = (here != null && (here[0] as Number) == _day) ? here[1] as Number : -1;

        var rowH = frac(0.136);
        var gap = 5;
        var top = frac(0.225);

        for (var row = 0; row < ROWS; row++) {
            var index = _scroll + row;
            if (index >= list.size()) { break; }
            var slot = _store.slot(_day, index);
            if (slot == null) { continue; }
            drawSlotRow(dc, slot, top + (row * rowH), rowH - gap, index == hereIndex);
        }

        // Position in the list, when it does not all fit.
        if (list.size() > ROWS) {
            centred(dc, frac(0.845), Graphics.FONT_XTINY, COL_DIM,
                    (_scroll + 1).toString() + "-"
                    + minOf(_scroll + ROWS, list.size()).toString()
                    + " of " + list.size().toString());
        }
    }

    private function drawSlotRow(dc as Dc, slot as Dictionary, y as Number,
                                 h as Number, isNow as Boolean) as Void {
        // Widest the row can be without touching the bezel at either edge.
        var dTop = y - _cy;
        var dBot = (y + h) - _cy;
        var dy = absOf(dTop) > absOf(dBot) ? absOf(dTop) : absOf(dBot);
        var half = chord(dy);
        var x = _cx - half;
        var w = half * 2;

        dc.setColor(isNow ? COL_CARD_HI : COL_CARD, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 8);

        // The kind rail down the left edge.
        dc.setColor(kindColour(TripStore.text(slot, "k", KIND_VISIT)), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, 6, h, 3);

        var textX = x + 16;
        var midY = y + (h / 2);

        dc.setColor(isNow ? COL_TEXT : COL_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, midY, Graphics.FONT_XTINY, TripStore.text(slot, "hm", "--:--"),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var timeW = dc.getTextWidthInPixels("00:00", Graphics.FONT_XTINY) + 12;
        var titleX = textX + timeW;
        var titleW = (x + w - 12) - titleX;
        var title = TripStore.text(slot, "ti", "");
        while (title.length() > 1
               && dc.getTextWidthInPixels(title, Graphics.FONT_XTINY) > titleW) {
            title = title.substring(0, title.length() - 1) as String;
        }

        dc.setColor(COL_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(titleX, midY, Graphics.FONT_XTINY, title,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---- page 2: the trip --------------------------------------------

    private function drawTrip(dc as Dc, now as Number) as Void {
        centred(dc, frac(0.115), Graphics.FONT_MEDIUM, COL_ACCENT,
                Fmt.clip(_store.destination(), 18));
        centred(dc, frac(0.195), Graphics.FONT_XTINY, COL_DIM,
                Fmt.clip(_store.dateRange(), 26));

        var stops = 0;
        for (var d = 0; d < _store.dayCount(); d++) { stops += _store.slots(d).size(); }

        var rows = [];
        if (!_store.origin().equals("")) { rows.add([ "From", Fmt.clip(_store.origin(), 16) ]); }
        if (!_store.hotel().equals(""))  { rows.add([ "Stay", Fmt.clip(_store.hotel(), 16) ]); }
        rows.add([ "Plan", _store.dayCount().toString() + " d, " + stops.toString() + " stops" ]);
        if (_store.budgetInr() > 0) { rows.add([ "Budget", Fmt.money(_store.budgetInr()) ]); }
        if (_store.co2Kg() > 0)     { rows.add([ "CO2", _store.co2Kg().toString() + " kg" ]); }

        var top = frac(0.30);
        var step = frac(0.088);
        for (var i = 0; i < rows.size() && i < 5; i++) {
            var row = rows[i] as Array;
            var y = top + (i * step);
            var half = chord(y - _cy);

            dc.setColor(COL_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx - half, y, Graphics.FONT_XTINY, row[0] as String,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COL_TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx + half, y, Graphics.FONT_XTINY, row[1] as String,
                        Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        drawBudgetBar(dc, frac(0.775));
        drawFooter(dc, now);
    }

    // Spend against the ceiling the traveller gave the planner. Amber once the
    // plan is over budget - the number alone is easy to miss at a glance.
    private function drawBudgetBar(dc as Dc, y as Number) as Void {
        var max = _store.budgetMaxInr();
        var spent = _store.budgetInr();
        if (max <= 0 || spent <= 0) { return; }

        var w = (_w * 0.44).toNumber();
        var x = _cx - (w / 2);
        var h = 8;

        dc.setColor(COL_CARD, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 4);

        var over = spent > max;
        var fill = over ? w : ((w * spent) / max);
        if (fill < 4) { fill = 4; }
        dc.setColor(over ? COL_WARN : COL_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, fill, h, 4);

        dc.setColor(COL_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, y + h + 14, Graphics.FONT_XTINY,
                    "of " + Fmt.money(max), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---- chrome ------------------------------------------------------

    private function drawEmpty(dc as Dc) as Void {
        centred(dc, frac(0.30), Graphics.FONT_XTINY, COL_ACCENT, "URBAN PULSE");

        var error = _store.getError();
        var lines = error != null
            ? wrap(dc, error, Graphics.FONT_SMALL, (_w * 0.72).toNumber(), 3)
            : wrap(dc, "Send an itinerary from the phone app to see it here",
                   Graphics.FONT_SMALL, (_w * 0.72).toNumber(), 3);

        var lineH = dc.getFontHeight(Graphics.FONT_SMALL);
        var top = _cy - (((lines.size() - 1) * lineH) / 2);
        for (var i = 0; i < lines.size(); i++) {
            centred(dc, top + (i * lineH), Graphics.FONT_SMALL,
                    error != null ? COL_WARN : COL_TEXT, lines[i] as String);
        }

        centred(dc, frac(0.80), Graphics.FONT_XTINY, COL_DIM, "START to sync");
        if (_syncing) { drawSyncArc(dc); }
    }

    private function drawFooter(dc as Dc, now as Number) as Void {
        var error = _store.getError();
        var text;
        var colour;
        if (error != null) {
            text = Fmt.clip(error, 26);
            colour = COL_WARN;
        } else if (_store.fetchedAt() > 0) {
            text = "synced " + Fmt.span(now - _store.fetchedAt()) + " ago";
            colour = COL_DIM;
        } else {
            text = "not synced yet";
            colour = COL_DIM;
        }
        centred(dc, frac(0.862), Graphics.FONT_XTINY, colour, text);
    }

    private function drawDots(dc as Dc) as Void {
        var y = frac(0.945);
        var gap = 16;
        var x0 = _cx - (((PAGES - 1) * gap) / 2);
        for (var i = 0; i < PAGES; i++) {
            dc.setColor(i == _page ? COL_ACCENT : COL_CARD, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + (i * gap), y, i == _page ? 4 : 3);
        }
    }

    // A quarter arc at the top edge while a request is in flight.
    private function drawSyncArc(dc as Dc) as Void {
        dc.setColor(COL_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawArc(_cx, _cy, _r - 4, Graphics.ARC_CLOCKWISE, 110, 70);
        dc.setPenWidth(1);
    }

    private function centred(dc as Dc, y as Number, font as Graphics.FontType,
                             colour as Number, text as String) as Void {
        if (text.equals("")) { return; }
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, y, font, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ------------------------------------------------------------------
    // Geometry
    // ------------------------------------------------------------------

    private function frac(f as Float) as Number { return (_h * f).toNumber(); }

    // Half the usable width at a vertical offset from the centre.
    private function chord(dy as Number) as Number {
        var d = absOf(dy);
        var inside = (_r * _r) - (d * d);
        if (inside < 1) { inside = 1; }
        var half = Math.sqrt(inside).toNumber() - 14;          // bezel margin
        var cap = (_w * 0.86).toNumber() / 2;
        if (half > cap) { half = cap; }
        if (half < 40) { half = 40; }
        return half;
    }

    // Greedy word wrap. Falls back to a hard cut for a single long word.
    private function wrap(dc as Dc, text as String, font as Graphics.FontType,
                          maxW as Number, maxLines as Number) as Array {
        var lines = [];
        var rest = text;

        while (rest.length() > 0 && lines.size() < maxLines) {
            if (dc.getTextWidthInPixels(rest, font) <= maxW) {
                lines.add(rest);
                return lines;
            }

            // Longest prefix that fits, cut back to a space when there is one.
            var cut = rest.length();
            while (cut > 1 && dc.getTextWidthInPixels(rest.substring(0, cut) as String, font) > maxW) {
                cut--;
            }
            var head = rest.substring(0, cut) as String;
            var space = Fmt.lastSpace(head);
            if (space > 0 && lines.size() < maxLines - 1) {
                head = rest.substring(0, space) as String;
                cut = space + 1;
            }

            if (lines.size() == maxLines - 1 && cut < rest.length()) {
                head = (head.length() > 3 ? head.substring(0, head.length() - 3) as String : head) + "...";
            }
            lines.add(head);
            rest = rest.substring(cut, rest.length()) as String;
        }
        return lines;
    }

    private function absOf(n as Number) as Number { return n < 0 ? -n : n; }
    private function minOf(a as Number, b as Number) as Number { return a < b ? a : b; }

    // ------------------------------------------------------------------
    // Interaction, driven by PulseDelegate
    // ------------------------------------------------------------------

    function page() as Number { return _page; }

    function nextPage() as Void {
        _page = (_page + 1) % PAGES;
        _scroll = 0;
    }

    function prevPage() as Void {
        _page = (_page + PAGES - 1) % PAGES;
        _scroll = 0;
    }

    function setPage(page as Number) as Void {
        _page = page;
        _scroll = 0;
    }

    // Scrolls the timeline, and rolls over into the neighbouring day at either
    // end so UP/DOWN walks the whole trip without changing mode.
    function scrollBy(delta as Number) as Void {
        var size = _store.slots(_day).size();
        var next = _scroll + delta;

        if (next < 0) {
            if (_day > 0) {
                moveDay(-1);
                var prevSize = _store.slots(_day).size();
                _scroll = prevSize > ROWS ? prevSize - ROWS : 0;
            } else {
                _scroll = 0;
            }
            return;
        }

        if (next + ROWS > size) {
            if (size > ROWS && next + ROWS <= size) { _scroll = next; return; }
            if (_day < _store.dayCount() - 1) { moveDay(1); _scroll = 0; return; }
            _scroll = size > ROWS ? size - ROWS : 0;
            return;
        }
        _scroll = next;
    }

    function moveDay(delta as Number) as Void {
        var last = _store.dayCount() - 1;
        if (last < 0) { return; }
        _day = _day + delta;
        if (_day < 0) { _day = 0; }
        if (_day > last) { _day = last; }
        _scroll = 0;
        _dayPinned = true;
    }

    // Back to whichever day the clock says, and back to following it.
    function followToday() as Void {
        _dayPinned = false;
        _day = _store.dayIndexFor(Time.now().value());
        _scroll = 0;
    }

    function dayIndex() as Number { return _day; }

    function setSyncing(syncing as Boolean) as Void { _syncing = syncing; }

    private function clampScroll(size as Number) as Void {
        var maxScroll = size > ROWS ? size - ROWS : 0;
        if (_scroll > maxScroll) { _scroll = maxScroll; }
        if (_scroll < 0) { _scroll = 0; }
    }


    // A new pairing code means a new store object behind the same view.
    function attach(store as TripStore) as Void {
        _store = store;
        _day = 0;
        _scroll = 0;
        _dayPinned = false;
    }

    // Which part of the screen a tap landed on. Geometry lives here, with the
    // layout that produced it, so the delegate stays free of coordinates.
    function hitTest(x as Number, y as Number) as Symbol {
        if (!_store.hasTrip()) { return :sync; }

        if (_page == PAGE_DAY) {
            if (y < frac(0.21)) { return x < _cx ? :prevDay : :nextDay; }
            return :today;
        }
        if (_page == PAGE_NEXT) { return :sync; }
        return :none;
    }

    // The countdown on the first page is only honest if it is redrawn. Half a
    // minute is under the resolution the text shows, and the screen is already
    // lit while the app is open.
    function onShow() as Void {
        if (_tick == null) { _tick = new Timer.Timer(); }
        (_tick as Timer.Timer).start(method(:onTick), 30 * 1000, true);
    }

    function onHide() as Void {
        if (_tick != null) { (_tick as Timer.Timer).stop(); }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    static function kindColour(kind as String) as Number {
        if (kind.equals(KIND_STAY))    { return COL_STAY; }
        if (kind.equals(KIND_MEAL))    { return COL_MEAL; }
        if (kind.equals(KIND_TRANSIT)) { return COL_TRANSIT; }
        if (kind.equals(KIND_REST))    { return COL_REST; }
        return COL_VISIT;
    }
}
