//
// Keypad - the key tables. Geometry lives in CalcView, because it is derived
// from dc.getWidth() at layout time and has nothing to do with which key is
// where.
//
// Two pages of a 4 x 4 grid. Swipe left/right, or UP/DOWN to move the button
// cursor and START to press.
//
import Toybox.Lang;

module Keypad {

    const COLS = 4;
    const ROWS = 4;
    const PAGES = 2;
    const COUNT = 16;                 // ROWS * COLS

    // Glyph coverage varies with firmware. If any of these three render as an
    // empty box on the watch, swap in the ASCII fallback in the comment - it is
    // the only change needed.
    const LBL_SQRT   = "√";      // fallback: "sqt"
    const LBL_SQUARE = "x²";     // fallback: "x2"
    const LBL_PI     = "π";      // fallback: "pi"

    // Index = row * COLS + col.
    function keysFor(page as Number) as Array {
        if (page == 0) {
            return [ :d7,  :d8,   :d9,     :div,
                     :d4,  :d5,   :d6,     :mul,
                     :d1,  :d2,   :d3,     :sub,
                     :d0,  :dot,  :equals, :add ];
        }
        return [ :lparen, :rparen, :clear,  :backspace,
                 :sqrt,   :square, :pow,    :pct,
                 :sin,    :cos,    :tan,    :pi,
                 :ln,     :log,    :ans,    :degrad ];
    }

    function labelFor(key as Symbol, degrees as Boolean) as String {
        switch (key) {
            case :d0:        return "0";
            case :d1:        return "1";
            case :d2:        return "2";
            case :d3:        return "3";
            case :d4:        return "4";
            case :d5:        return "5";
            case :d6:        return "6";
            case :d7:        return "7";
            case :d8:        return "8";
            case :d9:        return "9";
            case :dot:       return ".";
            case :add:       return "+";
            case :sub:       return "-";
            case :mul:       return "×";
            case :div:       return "÷";
            case :equals:    return "=";
            case :lparen:    return "(";
            case :rparen:    return ")";
            case :clear:     return "C";
            case :backspace: return "DEL";
            case :sqrt:      return LBL_SQRT;
            case :square:    return LBL_SQUARE;
            case :pow:       return "^";
            case :pct:       return "%";
            case :sin:       return "sin";
            case :cos:       return "cos";
            case :tan:       return "tan";
            case :pi:        return LBL_PI;
            case :ln:        return "ln";
            case :log:       return "log";
            case :ans:       return "ans";
            case :degrad:    return degrees ? "DEG" : "RAD";
        }
        return "?";
    }

    // Operators and actions are tinted; digits stay neutral.
    function isAccent(key as Symbol) as Boolean {
        return key == :add || key == :sub || key == :mul || key == :div
            || key == :pow || key == :pct || key == :square
            || key == :lparen || key == :rparen;
    }

    function isAction(key as Symbol) as Boolean {
        return key == :equals || key == :clear || key == :backspace || key == :degrad;
    }
}
