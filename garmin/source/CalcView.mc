//
// CalcView - everything that touches the screen.
//
// Not one coordinate is hard-coded to 454. Every position comes from
// dc.getWidth() / dc.getHeight() in onLayout(), and each keypad row is sized to
// the chord of the circle at that row's outermost edge:
//
//     halfWidth = sqrt(r^2 - dy^2)
//
// which is why the pad tapers towards the bottom instead of being clipped by
// the bezel.
//
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// AMOLED: black pixels cost no power, so the UI is dark with bright glyphs.
const COL_BG      = 0x000000;
const COL_KEY     = 0x151F26;
const COL_KEY_OP  = 0x10323F;
const COL_KEY_ACT = 0x1E2C34;
const COL_TEXT    = 0xE3ECF1;
const COL_DIM     = 0x7C9099;
const COL_ACCENT  = 0x45B7E7;
const COL_WARN    = 0xDEA34C;

class CalcView extends WatchUi.View {

    private var _engine as CalcEngine;

    private var _page as Number;
    private var _cursor as Number;               // -1 = touch mode, no highlight
    private var _pressed as Symbol or Null;
    private var _flash as Timer.Timer or Null;

    private var _w as Number;
    private var _h as Number;
    private var _cx as Number;
    private var _cy as Number;
    private var _r as Number;

    private var _statusY as Number;
    private var _exprY as Number;
    private var _resultY as Number;
    private var _resultBand as Number;
    private var _padTop as Number;
    private var _padBot as Number;

    private var _rects as Array;                 // flat x,y,w,h per key

    function initialize(engine as CalcEngine) {
        View.initialize();
        _engine = engine;
        _page = 0;
        _cursor = -1;
        _pressed = null;
        _flash = null;
        _w = 0;
        _h = 0;
        _cx = 0;
        _cy = 0;
        _r = 0;
        _statusY = 0;
        _exprY = 0;
        _resultY = 0;
        _resultBand = 0;
        _padTop = 0;
        _padBot = 0;
        _rects = [];
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        _r = _w / 2;

        _statusY = frac(0.088);          // DEG/RAD + page indicator
        _exprY   = frac(0.172);          // the expression being typed
        _padTop  = frac(0.368);
        _padBot  = frac(0.890);

        var bandTop = frac(0.215);
        _resultY = (bandTop + _padTop) / 2;
        _resultBand = _padTop - bandTop - 8;

        layoutKeys();
    }

    private function frac(f as Float) as Number {
        return (_h * f).toNumber();
    }

    private function layoutKeys() as Void {
        var gap = 6;
        var rows = Keypad.ROWS;
        var cols = Keypad.COLS;
        var cellH = ((_padBot - _padTop) - (gap * (rows - 1))) / rows;

        _rects = new [Keypad.COUNT * 4];

        for (var row = 0; row < rows; row++) {
            var y = _padTop + (row * (cellH + gap));

            // The row's usable width is the chord of the display circle at
            // whichever of its two edges sits further from the centre.
            var dTop = y - _cy;
            var dBot = (y + cellH) - _cy;
            if (dTop < 0) { dTop = -dTop; }
            if (dBot < 0) { dBot = -dBot; }
            var dy = dTop > dBot ? dTop : dBot;

            var inside = (_r * _r) - (dy * dy);
            if (inside < 1) { inside = 1; }
            var half = Math.sqrt(inside).toNumber() - 12;      // bezel margin

            var cap = (_w * 0.86).toNumber() / 2;              // keep the top row sane
            if (half > cap) { half = cap; }
            if (half < 40) { half = 40; }

            var cellW = ((half * 2) - (gap * (cols - 1))) / cols;
            var x0 = _cx - half;

            for (var col = 0; col < cols; col++) {
                var i = ((row * cols) + col) * 4;
                _rects[i]     = x0 + (col * (cellW + gap));
                _rects[i + 1] = y;
                _rects[i + 2] = cellW;
                _rects[i + 3] = cellH;
            }
        }
    }

    // ------------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------------

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COL_BG, COL_BG);
        dc.clear();

        drawStatus(dc);
        drawExpression(dc);
        drawResult(dc);
        drawKeys(dc);
    }

    private function drawStatus(dc as Dc) as Void {
        var edge = (_w * 0.30).toNumber();

        dc.setColor(_engine.isDegrees() ? COL_ACCENT : COL_WARN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx - edge, _statusY, Graphics.FONT_XTINY,
                    _engine.isDegrees() ? "DEG" : "RAD",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COL_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + edge, _statusY, Graphics.FONT_XTINY,
                    (_page + 1).toString() + "/" + Keypad.PAGES.toString(),
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawExpression(dc as Dc) as Void {
        var text = _engine.getExpression();
        if (text.length() == 0) { return; }

        var maxW = (_w * 0.74).toNumber();
        // Keep the tail - that is where the cursor conceptually is.
        while (text.length() > 1 && dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > maxW) {
            text = text.substring(1, text.length()) as String;
        }

        dc.setColor(COL_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _exprY, Graphics.FONT_XTINY, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawResult(dc as Dc) as Void {
        var text = _engine.getDisplay();
        var err = _engine.getError();
        var maxW = (_w * 0.84).toNumber();

        var fonts;
        if (err != null || hasLetters(text)) {
            // The FONT_NUMBER_* faces contain digits only - error text and
            // scientific notation have to use a text font.
            fonts = [ Graphics.FONT_LARGE, Graphics.FONT_MEDIUM,
                      Graphics.FONT_SMALL, Graphics.FONT_XTINY ];
        } else {
            fonts = [ Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM,
                      Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE,
                      Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_XTINY ];
        }

        dc.setColor(err != null ? COL_WARN : COL_TEXT, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < fonts.size(); i++) {
            var f = fonts[i];
            var fits = dc.getTextWidthInPixels(text, f) <= maxW
                    && dc.getFontHeight(f) <= _resultBand;
            if (fits || i == fonts.size() - 1) {
                dc.drawText(_cx, _resultY, f, text,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }
        }
    }

    private function drawKeys(dc as Dc) as Void {
        var keys = Keypad.keysFor(_page);

        for (var i = 0; i < Keypad.COUNT; i++) {
            var x = _rects[i * 4] as Number;
            var y = _rects[(i * 4) + 1] as Number;
            var w = _rects[(i * 4) + 2] as Number;
            var h = _rects[(i * 4) + 3] as Number;
            var key = keys[i] as Symbol;

            var down = (_pressed != null) && (_pressed == key);

            var bg = COL_KEY;
            if (Keypad.isAccent(key)) { bg = COL_KEY_OP; }
            if (Keypad.isAction(key)) { bg = COL_KEY_ACT; }
            if (down) { bg = COL_ACCENT; }

            dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, w, h, 6);

            if (_cursor == i) {
                dc.setColor(COL_ACCENT, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                dc.drawRoundedRectangle(x, y, w, h, 6);
                dc.setPenWidth(1);
            }

            var label = Keypad.labelFor(key, _engine.isDegrees());
            dc.setColor(down ? COL_BG : COL_TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + (w / 2), y + (h / 2), labelFont(dc, label, w - 8), label,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function labelFont(dc as Dc, label as String, maxW as Number) {
        if (dc.getTextWidthInPixels(label, Graphics.FONT_SMALL) <= maxW) {
            return Graphics.FONT_SMALL;
        }
        return Graphics.FONT_XTINY;
    }

    private function hasLetters(s as String) as Boolean {
        var letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
        for (var i = 0; i < s.length(); i++) {
            if (letters.find(s.substring(i, i + 1) as String) != null) { return true; }
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Interaction, driven by CalcDelegate
    // ------------------------------------------------------------------

    // Returns the key at a screen coordinate, or null if the tap missed.
    function keyAt(x as Number, y as Number) as Symbol or Null {
        var keys = Keypad.keysFor(_page);
        for (var i = 0; i < Keypad.COUNT; i++) {
            var kx = _rects[i * 4] as Number;
            var ky = _rects[(i * 4) + 1] as Number;
            var kw = _rects[(i * 4) + 2] as Number;
            var kh = _rects[(i * 4) + 3] as Number;
            if (x >= kx && x <= kx + kw && y >= ky && y <= ky + kh) {
                return keys[i] as Symbol;
            }
        }
        return null;
    }

    function cursorKey() as Symbol or Null {
        if (_cursor < 0) { return null; }
        return Keypad.keysFor(_page)[_cursor] as Symbol;
    }

    function moveCursor(delta as Number) as Void {
        if (_cursor < 0) {
            _cursor = delta > 0 ? 0 : Keypad.COUNT - 1;
            return;
        }
        _cursor = _cursor + delta;
        if (_cursor < 0) { _cursor = Keypad.COUNT - 1; }
        if (_cursor >= Keypad.COUNT) { _cursor = 0; }
    }

    function nextPage() as Void { _page = (_page + 1) % Keypad.PAGES; }
    function prevPage() as Void { _page = (_page + Keypad.PAGES - 1) % Keypad.PAGES; }

    // A short highlight so a press is visible without looking at your hand.
    function flashKey(key as Symbol) as Void {
        _pressed = key;
        if (_flash == null) { _flash = new Timer.Timer(); }
        _flash.start(method(:clearFlash), 120, false);
    }

    function clearFlash() as Void {
        _pressed = null;
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        if (_flash != null) { _flash.stop(); }
        _pressed = null;
    }
}
