//
// CalcEngine - all of the arithmetic, none of the drawing.
//
// The engine never touches Dc, WatchUi or any resource, which is what makes it
// runnable from the unit tests in tests/EngineTest.mc. It tokenises an ASCII
// expression, converts it to RPN with the shunting-yard algorithm, and
// evaluates the RPN on a stack machine. Everything is held as Lang.Double and
// rounded only at the display boundary.
//
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Error text lives here, not in strings.xml, so the engine has no resource
// dependency and the tests can run it standalone.
const CALC_ERR_SYNTAX    = "Syntax error";
const CALC_ERR_DIV_ZERO  = "Divide by zero";
const CALC_ERR_UNDEFINED = "Undefined";
const CALC_ERR_OVERFLOW  = "Overflow";
const CALC_ERR_TOO_LONG  = "Too long";

const CALC_MAX_INPUT   = 48;   // characters accepted in one expression
const CALC_MAX_TOKENS  = 72;
const CALC_MAX_STACK   = 32;
const CALC_MAX_HISTORY = 12;

// One token of the expression. A tiny class beats a mixed-type Array because
// it keeps the type checker happy and makes the evaluator readable.
class Tok {
    public var kind as Symbol;   // :num  :op  :fn  :lp  :rp
    public var num as Double;
    public var op as String;

    function initialize(k as Symbol, n as Double, o as String) {
        kind = k;
        num = n;
        op = o;
    }
}

class CalcEngine {

    private var _expr as String;            // canonical ASCII, e.g. "2+3*sqrt(9)"
    private var _display as String;         // the big number (or an error)
    private var _error as String or Null;
    private var _degrees as Boolean;
    private var _haptics as Boolean;
    private var _decimals as Number;
    private var _history as Array;          // Array<String>, newest first
    private var _ans as Double;
    private var _justEvaluated as Boolean;

    function initialize() {
        _expr = "";
        _display = "0";
        _error = null;
        _degrees = true;
        _haptics = true;
        _decimals = 10;
        _history = [];
        _ans = 0.0d;
        _justEvaluated = false;
    }

    // ------------------------------------------------------------------
    // What the view reads
    // ------------------------------------------------------------------

    function getDisplay() as String { return _display; }
    function getExpression() as String { return displayForm(_expr); }
    function getError() as String or Null { return _error; }
    function hasEntry() as Boolean { return _expr.length() > 0; }
    function isDegrees() as Boolean { return _degrees; }
    function hapticsOn() as Boolean { return _haptics; }
    function getHistory() as Array { return _history; }

    function setDegrees(on as Boolean) as Void { _degrees = on; }
    function setHaptics(on as Boolean) as Void { _haptics = on; }

    function setDecimals(n as Number) as Void {
        if (n < 0) { n = 0; }
        if (n > 12) { n = 12; }
        _decimals = n;
    }

    // ------------------------------------------------------------------
    // Input
    // ------------------------------------------------------------------

    function press(key as Symbol) as Void {
        if (key == :clear)     { clearAll(); return; }
        if (key == :backspace) { backspace(); return; }
        if (key == :equals)    { evaluate(); return; }
        if (key == :degrad)    { _degrees = !_degrees; updatePreview(); return; }

        var t = tokenFor(key);
        if (t == null) { return; }

        if (_justEvaluated) {
            _justEvaluated = false;
            // An operator continues from the answer; anything else starts over.
            if (isContinuation(t)) {
                _expr = "ans";
            } else {
                _expr = "";
            }
        }

        _error = null;

        if (_expr.length() + t.length() > CALC_MAX_INPUT) {
            _error = CALC_ERR_TOO_LONG;
            _display = CALC_ERR_TOO_LONG;
            return;
        }

        _expr = _expr + t;
        updatePreview();
    }

    function clearAll() as Void {
        _expr = "";
        _display = "0";
        _error = null;
        _justEvaluated = false;
    }

    function backspace() as Void {
        _error = null;

        if (_justEvaluated) { clearAll(); return; }

        // Multi-character tokens are deleted whole - "sqrt(" is one key press,
        // so it is one delete.
        var multi = [ "sqrt(", "sin(", "cos(", "tan(", "log(", "ln(", "ans", "pi", "^2" ];
        for (var i = 0; i < multi.size(); i++) {
            var m = multi[i] as String;
            if (endsWith(_expr, m)) {
                _expr = _expr.substring(0, _expr.length() - m.length()) as String;
                afterEdit();
                return;
            }
        }

        if (_expr.length() > 0) {
            _expr = _expr.substring(0, _expr.length() - 1) as String;
        }
        afterEdit();
    }

    private function afterEdit() as Void {
        if (_expr.length() == 0) {
            _display = "0";
        } else {
            updatePreview();
        }
    }

    // ------------------------------------------------------------------
    // Evaluation
    // ------------------------------------------------------------------

    function evaluate() as Void {
        if (_expr.length() == 0) { _display = "0"; return; }

        var v = evaluateValue(_expr);
        if (v == null) {
            if (_error == null) { _error = CALC_ERR_SYNTAX; }
            _display = _error as String;
            return;
        }

        _ans = v;
        _error = null;
        _display = formatValue(v);
        addHistory(displayForm(_expr) + " = " + _display);
        _justEvaluated = true;
    }

    // Evaluate without disturbing the error state - used for the live preview
    // that sits under the expression while the user is still typing.
    private function updatePreview() as Void {
        var previous = _display;
        var v = evaluateValue(_expr);
        _error = null;                       // a half-typed expression is not an error
        if (v != null) {
            _display = formatValue(v);
        } else {
            _display = previous;
        }
    }

    // The whole pipeline, exposed so the tests can drive it directly.
    function evaluateValue(src as String) as Double or Null {
        _error = null;

        if (src.length() == 0) { _error = CALC_ERR_SYNTAX; return null; }
        if (src.length() > CALC_MAX_INPUT) { _error = CALC_ERR_TOO_LONG; return null; }

        var toks = tokenize(src);
        if (toks == null) { setSyntaxIfUnset(); return null; }

        var rpn = toRpn(toks as Array);
        if (rpn == null) { setSyntaxIfUnset(); return null; }

        return evalRpn(rpn as Array);
    }

    // Convenience for the tests: evaluate and format in one call.
    function evaluateToString(src as String) as String {
        var v = evaluateValue(src);
        if (v == null) {
            if (_error == null) { return CALC_ERR_SYNTAX; }
            return _error as String;
        }
        return formatValue(v);
    }

    private function setSyntaxIfUnset() as Void {
        if (_error == null) { _error = CALC_ERR_SYNTAX; }
    }

    // ------------------------------------------------------------------
    // Tokeniser
    // ------------------------------------------------------------------

    private function tokenize(src as String) as Array or Null {
        var toks = new [CALC_MAX_TOKENS];
        var n = 0;
        var i = 0;
        var len = src.length();
        var prev = :none;                    // :none :num :op :lp :rp :fn

        while (i < len) {
            if (n >= CALC_MAX_TOKENS - 2) { _error = CALC_ERR_TOO_LONG; return null; }

            var ch = src.substring(i, i + 1) as String;

            if (isDigit(ch) || ch.equals(".")) {
                var start = i;
                var seenDot = false;
                while (i < len) {
                    var c = src.substring(i, i + 1) as String;
                    if (isDigit(c)) {
                        i++;
                    } else if (c.equals(".") && !seenDot) {
                        seenDot = true;
                        i++;
                    } else {
                        break;
                    }
                }
                var numStr = src.substring(start, i) as String;
                if (endsWith(numStr, ".")) { numStr = numStr + "0"; }
                if (numStr.equals(".0")) { numStr = "0.0"; }
                var v = numStr.toDouble();
                if (v == null) { return null; }

                if (prev == :num || prev == :rp) { return null; }   // "2 3" is not a thing
                toks[n] = new Tok(:num, v as Double, "");
                n++;
                prev = :num;

            } else if (isAlpha(ch)) {
                var nameStart = i;
                while (i < len && isAlpha(src.substring(i, i + 1) as String)) { i++; }
                var name = src.substring(nameStart, i) as String;

                // "2pi" and "(1+2)ans" mean multiplication
                if (prev == :num || prev == :rp) {
                    toks[n] = new Tok(:op, 0.0d, "*");
                    n++;
                }

                if (name.equals("pi")) {
                    toks[n] = new Tok(:num, Math.PI.toDouble(), "");
                    n++;
                    prev = :num;
                } else if (name.equals("e")) {
                    toks[n] = new Tok(:num, Math.E.toDouble(), "");
                    n++;
                    prev = :num;
                } else if (name.equals("ans")) {
                    toks[n] = new Tok(:num, _ans, "");
                    n++;
                    prev = :num;
                } else if (isFunction(name)) {
                    toks[n] = new Tok(:fn, 0.0d, name);
                    n++;
                    prev = :fn;
                } else {
                    return null;
                }

            } else if (ch.equals("(")) {
                if (prev == :num || prev == :rp) {              // "2(3+4)"
                    toks[n] = new Tok(:op, 0.0d, "*");
                    n++;
                }
                toks[n] = new Tok(:lp, 0.0d, "(");
                n++;
                prev = :lp;
                i++;

            } else if (ch.equals(")")) {
                if (prev == :none || prev == :op || prev == :lp || prev == :fn) { return null; }
                toks[n] = new Tok(:rp, 0.0d, ")");
                n++;
                prev = :rp;
                i++;

            } else if (ch.equals("%")) {
                if (!(prev == :num || prev == :rp)) { return null; }
                toks[n] = new Tok(:op, 0.0d, "%");              // postfix: x/100
                n++;
                prev = :num;                                    // behaves like an operand
                i++;

            } else if (isOperator(ch)) {
                var leading = (prev == :none || prev == :op || prev == :lp || prev == :fn);
                if (leading) {
                    if (ch.equals("-")) {
                        toks[n] = new Tok(:op, 0.0d, "u");      // unary minus
                        n++;
                    } else if (ch.equals("+")) {
                        // a leading "+" is a no-op; drop it
                    } else {
                        return null;                            // "*3" etc.
                    }
                } else {
                    toks[n] = new Tok(:op, 0.0d, ch);
                    n++;
                }
                prev = :op;
                i++;

            } else {
                return null;                                     // unknown character
            }
        }

        if (n == 0) { return null; }
        return toks.slice(0, n);
    }

    // ------------------------------------------------------------------
    // Shunting-yard: infix tokens -> RPN
    // ------------------------------------------------------------------

    private function toRpn(toks as Array) as Array or Null {
        var out = new [CALC_MAX_TOKENS];
        var on = 0;
        var ops = new [CALC_MAX_TOKENS];
        var sp = 0;

        for (var i = 0; i < toks.size(); i++) {
            var t = toks[i] as Tok;

            if (t.kind == :num) {
                out[on] = t;
                on++;

            } else if (t.kind == :fn) {
                ops[sp] = t;
                sp++;

            } else if (t.kind == :op) {
                if (t.op.equals("%")) {
                    out[on] = t;                                 // postfix, applies now
                    on++;
                } else {
                    while (sp > 0) {
                        var top = ops[sp - 1] as Tok;
                        if (top.kind == :lp) { break; }
                        var stronger = (top.kind == :fn)
                            || (precedence(top) > precedence(t))
                            || (precedence(top) == precedence(t) && !isRightAssoc(t));
                        if (!stronger) { break; }
                        sp--;
                        out[on] = top;
                        on++;
                    }
                    ops[sp] = t;
                    sp++;
                }

            } else if (t.kind == :lp) {
                ops[sp] = t;
                sp++;

            } else {                                             // :rp
                var matched = false;
                while (sp > 0) {
                    var top2 = ops[sp - 1] as Tok;
                    sp--;
                    if (top2.kind == :lp) { matched = true; break; }
                    out[on] = top2;
                    on++;
                }
                if (!matched) { return null; }                   // stray ")"
                if (sp > 0 && (ops[sp - 1] as Tok).kind == :fn) {
                    sp--;
                    out[on] = ops[sp] as Tok;
                    on++;
                }
            }
        }

        while (sp > 0) {
            sp--;
            var rest = ops[sp] as Tok;
            if (rest.kind == :lp) { return null; }               // unbalanced "("
            out[on] = rest;
            on++;
        }

        return out.slice(0, on);
    }

    private function precedence(t as Tok) as Number {
        var o = t.op;
        if (o.equals("+") || o.equals("-")) { return 1; }
        if (o.equals("*") || o.equals("/")) { return 2; }
        if (o.equals("u")) { return 3; }
        if (o.equals("^")) { return 4; }
        return 5;
    }

    private function isRightAssoc(t as Tok) as Boolean {
        return t.op.equals("^") || t.op.equals("u");
    }

    // ------------------------------------------------------------------
    // RPN evaluation
    // ------------------------------------------------------------------

    private function evalRpn(rpn as Array) as Double or Null {
        var st = new [CALC_MAX_STACK];
        var sp = 0;

        for (var i = 0; i < rpn.size(); i++) {
            var t = rpn[i] as Tok;

            if (t.kind == :num) {
                if (sp >= CALC_MAX_STACK) { _error = CALC_ERR_TOO_LONG; return null; }
                st[sp] = t.num;
                sp++;

            } else if (t.kind == :fn) {
                if (sp < 1) { _error = CALC_ERR_SYNTAX; return null; }
                var r = applyFunction(t.op, st[sp - 1] as Double);
                if (r == null) { return null; }
                st[sp - 1] = r;

            } else if (t.op.equals("u")) {
                if (sp < 1) { _error = CALC_ERR_SYNTAX; return null; }
                st[sp - 1] = -(st[sp - 1] as Double);

            } else if (t.op.equals("%")) {
                if (sp < 1) { _error = CALC_ERR_SYNTAX; return null; }
                st[sp - 1] = (st[sp - 1] as Double) / 100.0d;

            } else {
                if (sp < 2) { _error = CALC_ERR_SYNTAX; return null; }
                var b = st[sp - 1] as Double;
                var a = st[sp - 2] as Double;
                sp--;
                var v = applyBinary(t.op, a, b);
                if (v == null) { return null; }
                st[sp - 1] = v;
            }
        }

        if (sp != 1) { _error = CALC_ERR_SYNTAX; return null; }
        return finite(st[0] as Double);
    }

    private function applyBinary(op as String, a as Double, b as Double) as Double or Null {
        if (op.equals("+")) { return finite(a + b); }
        if (op.equals("-")) { return finite(a - b); }
        if (op.equals("*")) { return finite(a * b); }
        if (op.equals("/")) {
            if (b == 0.0d) { _error = CALC_ERR_DIV_ZERO; return null; }
            return finite(a / b);
        }
        if (op.equals("^")) {
            // A negative base with a fractional exponent is not a real number.
            if (a < 0.0d && (b != Math.round(b).toDouble())) {
                _error = CALC_ERR_UNDEFINED;
                return null;
            }
            if (a == 0.0d && b < 0.0d) { _error = CALC_ERR_DIV_ZERO; return null; }
            return finite(Math.pow(a, b).toDouble());
        }
        _error = CALC_ERR_SYNTAX;
        return null;
    }

    private function applyFunction(name as String, a as Double) as Double or Null {
        if (name.equals("sqrt")) {
            if (a < 0.0d) { _error = CALC_ERR_UNDEFINED; return null; }
            return finite(Math.sqrt(a).toDouble());
        }
        if (name.equals("ln")) {
            if (a <= 0.0d) { _error = CALC_ERR_UNDEFINED; return null; }
            return finite(Math.ln(a).toDouble());
        }
        if (name.equals("log")) {
            if (a <= 0.0d) { _error = CALC_ERR_UNDEFINED; return null; }
            // Toybox.Math.log() takes an explicit base - Math.ln() is the natural log.
            return finite(Math.log(a, 10).toDouble());
        }
        if (name.equals("sin")) { return finite(Math.sin(toAngle(a)).toDouble()); }
        if (name.equals("cos")) { return finite(Math.cos(toAngle(a)).toDouble()); }
        if (name.equals("tan")) { return finite(Math.tan(toAngle(a)).toDouble()); }

        _error = CALC_ERR_SYNTAX;
        return null;
    }

    private function toAngle(a as Double) as Double {
        if (_degrees) { return Math.toRadians(a).toDouble(); }
        return a;
    }

    // Infinity and NaN both fail (v * 0 == 0), which is how overflow is caught
    // without relying on a literal for the Double maximum.
    private function finite(v as Double) as Double or Null {
        if ((v * 0.0d) == 0.0d) { return v; }
        _error = CALC_ERR_OVERFLOW;
        return null;
    }

    // ------------------------------------------------------------------
    // Display formatting - the only place rounding happens
    // ------------------------------------------------------------------

    function formatValue(v as Double) as String {
        if ((v * 0.0d) != 0.0d) { return CALC_ERR_OVERFLOW; }
        if (v == 0.0d) { return "0"; }

        var neg = v < 0.0d;
        var a = v;
        if (neg) { a = -a; }

        var big = Math.pow(10, 12).toDouble();
        var small = Math.pow(10, -9).toDouble();
        if (a >= big || a < small) { return scientific(v); }

        var s = a.format("%." + _decimals.toString() + "f");
        s = trimZeros(s);
        if (s.equals("0") || s.equals("")) { return "0"; }    // rounded away to nothing
        if (neg) { s = "-" + s; }
        return s;
    }

    private function scientific(v as Double) as String {
        var neg = v < 0.0d;
        var a = v;
        if (neg) { a = -a; }

        var exp = 0;
        var ten = 10.0d;
        while (a >= ten && exp < 320) { a = a / ten; exp++; }
        while (a < 1.0d && exp > -320) { a = a * ten; exp--; }
        // Round the mantissa to the digits that will actually be shown before
        // testing the 10 boundary - otherwise 1e-11, which accumulates to
        // 9.999999999999998 above, prints as "10e-12".
        var million = 1000000.0d;
        var mantissa = Math.round(a * million).toDouble() / million;
        if (mantissa >= ten) {
            mantissa = mantissa / ten;
            exp++;
        }

        var m = trimZeros(mantissa.format("%.6f"));
        var s = m + "e" + exp.toString();
        if (neg) { s = "-" + s; }
        return s;
    }

    private function trimZeros(s as String) as String {
        if (s.find(".") == null) { return s; }
        while (s.length() > 0 && endsWith(s, "0")) {
            s = s.substring(0, s.length() - 1) as String;
        }
        if (endsWith(s, ".")) {
            s = s.substring(0, s.length() - 1) as String;
        }
        return s;
    }

    // Canonical ASCII -> what the user should see on a watch face.
    function displayForm(src as String) as String {
        var s = replaceAll(src, "sqrt(", "√(");
        s = replaceAll(s, "*", "×");
        s = replaceAll(s, "/", "÷");
        s = replaceAll(s, "pi", "π");
        return s;
    }

    // ------------------------------------------------------------------
    // History (persisted by the app object)
    // ------------------------------------------------------------------

    private function addHistory(line as String) as Void {
        var next = [line];
        for (var i = 0; i < _history.size() && i < CALC_MAX_HISTORY - 1; i++) {
            next.add(_history[i]);
        }
        _history = next;
    }

    function clearHistory() as Void { _history = []; }

    function exportHistory() as Array { return _history; }

    function restoreHistory(saved as Array) as Void {
        _history = [];
        for (var i = 0; i < saved.size() && i < CALC_MAX_HISTORY; i++) {
            var line = saved[i];
            if (line instanceof String) { _history.add(line); }
        }
    }

    // ------------------------------------------------------------------
    // Small helpers
    // ------------------------------------------------------------------

    private function tokenFor(key as Symbol) as String or Null {
        switch (key) {
            case :d0:     return "0";
            case :d1:     return "1";
            case :d2:     return "2";
            case :d3:     return "3";
            case :d4:     return "4";
            case :d5:     return "5";
            case :d6:     return "6";
            case :d7:     return "7";
            case :d8:     return "8";
            case :d9:     return "9";
            case :dot:    return ".";
            case :add:    return "+";
            case :sub:    return "-";
            case :mul:    return "*";
            case :div:    return "/";
            case :pow:    return "^";
            case :square: return "^2";
            case :lparen: return "(";
            case :rparen: return ")";
            case :pct:    return "%";
            case :sqrt:   return "sqrt(";
            case :sin:    return "sin(";
            case :cos:    return "cos(";
            case :tan:    return "tan(";
            case :ln:     return "ln(";
            case :log:    return "log(";
            case :pi:     return "pi";
            case :euler:  return "e";
            case :ans:    return "ans";
        }
        return null;
    }

    // Tokens that carry on from the previous answer rather than starting fresh.
    private function isContinuation(t as String) as Boolean {
        return t.equals("+") || t.equals("-") || t.equals("*") || t.equals("/")
            || t.equals("^") || t.equals("^2") || t.equals("%") || t.equals(")");
    }

    private function isFunction(name as String) as Boolean {
        return name.equals("sqrt") || name.equals("sin") || name.equals("cos")
            || name.equals("tan") || name.equals("ln") || name.equals("log");
    }

    private function isDigit(ch as String) as Boolean {
        return "0123456789".find(ch) != null;
    }

    private function isAlpha(ch as String) as Boolean {
        return "abcdefghijklmnopqrstuvwxyz".find(ch) != null;
    }

    private function isOperator(ch as String) as Boolean {
        return ch.equals("+") || ch.equals("-") || ch.equals("*")
            || ch.equals("/") || ch.equals("^");
    }

    private function endsWith(s as String, suffix as String) as Boolean {
        var n = suffix.length();
        if (s.length() < n || n == 0) { return false; }
        return (s.substring(s.length() - n, s.length()) as String).equals(suffix);
    }

    // Lang.String has no replace(), so here is one.
    private function replaceAll(s as String, from as String, to as String) as String {
        var n = from.length();
        if (n == 0) { return s; }
        var out = "";
        var i = 0;
        while (i < s.length()) {
            if (i + n <= s.length() && (s.substring(i, i + n) as String).equals(from)) {
                out = out + to;
                i = i + n;
            } else {
                out = out + (s.substring(i, i + 1) as String);
                i++;
            }
        }
        return out;
    }
}
