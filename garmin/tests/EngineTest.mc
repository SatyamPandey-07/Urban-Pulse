//
// Run No Evil tests for the calculator engine.
//
// These run in the simulator only and are stripped from release builds, so they
// cost nothing on the watch. The engine has no UI dependency, which is what
// makes all of this testable in the first place.
//
//   Test Explorer in VS Code (the flask icon), or:
//   monkeyc -f monkey.jungle -d fr965 -o bin/test.prg -y <key>.der --unit-test
//   monkeydo bin/test.prg fr965 -t
//
import Toybox.Lang;
import Toybox.Test;

(:test)
function testOperatorPrecedence(logger as Logger) as Boolean {
    var e = new CalcEngine();
    var r = e.evaluateToString("2+3*4");
    logger.debug("2+3*4 = " + r);
    return r.equals("14");                 // not 20 - this is the whole point
}

(:test)
function testParentheses(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateToString("(2+3)*4").equals("20");
}

(:test)
function testFloatingPointDisplay(logger as Logger) as Boolean {
    var e = new CalcEngine();
    var r = e.evaluateToString("0.1+0.2");
    logger.debug("0.1+0.2 = " + r);
    return r.equals("0.3");                // rounded at the display, not in the engine
}

(:test)
function testUnaryMinusBindsLooserThanPower(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateToString("-2^2").equals("-4");
}

(:test)
function testPowerIsRightAssociative(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateToString("2^3^2").equals("512");
}

(:test)
function testImplicitMultiplication(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateToString("2(3+4)").equals("14");
}

(:test)
function testPercentIsPostfix(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateToString("50%+10").equals("10.5");
}

(:test)
function testSquareRoot(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateToString("sqrt(9)").equals("3");
}

(:test)
function testLogIsBaseTen(logger as Logger) as Boolean {
    var e = new CalcEngine();
    // Toybox.Math.log() takes a base; Math.ln() is the natural log.
    return e.evaluateToString("log(100)").equals("2") && e.evaluateToString("ln(1)").equals("0");
}

(:test)
function testTrigUsesDegreesByDefault(logger as Logger) as Boolean {
    var e = new CalcEngine();
    var deg = e.evaluateToString("sin(30)");
    logger.debug("sin(30) in DEG = " + deg);
    e.setDegrees(false);
    var rad = e.evaluateToString("sin(0)");
    return deg.equals("0.5") && rad.equals("0");
}

(:test)
function testDivideByZero(logger as Logger) as Boolean {
    var e = new CalcEngine();
    var v = e.evaluateValue("5/0");
    return v == null && e.getError() != null;        // errors, does not crash
}

(:test)
function testSqrtOfNegativeIsUndefined(logger as Logger) as Boolean {
    var e = new CalcEngine();
    var v = e.evaluateValue("sqrt(-4)");
    var err = e.getError();
    return v == null && err != null && (err as String).equals(CALC_ERR_UNDEFINED);
}

(:test)
function testUnbalancedParens(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateValue("(2+3") == null && e.evaluateValue("2+3)") == null;
}

(:test)
function testDanglingOperator(logger as Logger) as Boolean {
    var e = new CalcEngine();
    return e.evaluateValue("2+") == null && e.evaluateValue("*3") == null;
}

(:test)
function testOverlongInputIsRejected(logger as Logger) as Boolean {
    var e = new CalcEngine();
    var long = "1";
    for (var i = 0; i < 60; i++) { long = long + "+1"; }
    var v = e.evaluateValue(long);
    var err = e.getError();
    return v == null && err != null && (err as String).equals(CALC_ERR_TOO_LONG);
}

(:test)
function testKeyPressesDriveTheDisplay(logger as Logger) as Boolean {
    var e = new CalcEngine();
    e.press(:d2);
    e.press(:add);
    e.press(:d3);
    var preview = e.getDisplay();                    // live preview before "="
    e.press(:equals);
    logger.debug("preview=" + preview + " result=" + e.getDisplay());
    return preview.equals("5") && e.getDisplay().equals("5") && e.getHistory().size() == 1;
}

(:test)
function testBackspaceDeletesWholeFunctionToken(logger as Logger) as Boolean {
    var e = new CalcEngine();
    e.press(:sqrt);                                  // appends "sqrt("
    e.press(:backspace);                             // one press removes all five chars
    return !e.hasEntry();
}

(:test)
function testAnswerCarriesIntoTheNextExpression(logger as Logger) as Boolean {
    var e = new CalcEngine();
    e.press(:d8);
    e.press(:equals);
    e.press(:add);                                   // operator continues from "ans"
    e.press(:d2);
    e.press(:equals);
    return e.getDisplay().equals("10");
}

(:test)
function testHistoryIsCapped(logger as Logger) as Boolean {
    var e = new CalcEngine();
    for (var i = 0; i < CALC_MAX_HISTORY + 5; i++) {
        e.press(:d1);
        e.press(:add);
        e.press(:d1);
        e.press(:equals);
    }
    return e.getHistory().size() == CALC_MAX_HISTORY;
}
