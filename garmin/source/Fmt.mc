//
// Fmt - pure formatting and geometry helpers. No Dc, no Storage, no network.
//
// Everything here is a function of its arguments only, which is what lets the
// whole module be exercised from the unit tests in tests/. Device-dependent
// inputs (metric vs statute) are passed in rather than read from System, for
// the same reason.
//
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

module Fmt {

    // Debug builds print; release builds compile this away entirely. It is how
    // a sync is verified in the simulator console.
    (:debug)
    function log(message as String) as Void {
        System.println(message);
    }

    (:release)
    function log(message as String) as Void {
    }


    // 42000 -> "42,000". Monkey C has no locale-aware grouping.
    function grouped(n as Number) as String {
        var neg = n < 0;
        var digits = (neg ? -n : n).toString();
        var out = "";
        var run = 0;

        for (var i = digits.length() - 1; i >= 0; i--) {
            out = (digits.substring(i, i + 1) as String) + out;
            run++;
            if (run % 3 == 0 && i > 0) { out = "," + out; }
        }
        return neg ? "-" + out : out;
    }

    // Rupees. The watch fonts carry no rupee glyph, so "Rs" it is.
    function money(n as Number) as String {
        return "Rs " + grouped(n);
    }

    // A duration as a human span: "45 min", "2 h 10", "3 d". Always positive -
    // the caller decides whether it reads "in ..." or "... ago".
    function span(seconds as Number) as String {
        var s = seconds < 0 ? -seconds : seconds;
        if (s < 60) { return "<1 min"; }

        var mins = s / 60;
        if (mins < 60) { return mins.toString() + " min"; }

        var hours = mins / 60;
        var restMin = mins % 60;
        if (hours < 24) {
            return restMin == 0 ? hours.toString() + " h"
                                : hours.toString() + " h " + restMin.toString();
        }

        var days = hours / 24;
        var restHour = hours % 24;
        return restHour == 0 ? days.toString() + " d"
                             : days.toString() + " d " + restHour.toString() + " h";
    }

    // Metres in the user's unit, rounded the way a walking distance is read.
    function distance(metres as Float, metric as Boolean) as String {
        if (metric) {
            if (metres < 950) { return ((metres / 10).toNumber() * 10).toString() + " m"; }
            return (metres / 1000.0).format("%.1f") + " km";
        }
        var feet = metres * 3.28084;
        if (feet < 1500) { return ((feet / 10).toNumber() * 10).toString() + " ft"; }
        return (metres / 1609.344).format("%.1f") + " mi";
    }

    // A true bearing as one of the eight points - all that is legible at this
    // size, and all that is honest without a calibrated compass.
    function compass(bearingDeg as Float) as String {
        var points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        var b = bearingDeg;
        while (b < 0) { b += 360; }
        while (b >= 360) { b -= 360; }
        var i = ((b + 22.5) / 45).toNumber() % 8;
        return points[i] as String;
    }

    // Great-circle bearing from one position to another, in degrees true.
    function bearingBetween(fromLat as Float, fromLon as Float,
                            toLat as Float, toLon as Float) as Float {
        var f1 = toRad(fromLat);
        var f2 = toRad(toLat);
        var dl = toRad(toLon - fromLon);

        var y = Math.sin(dl) * Math.cos(f2);
        var x = (Math.cos(f1) * Math.sin(f2)) - (Math.sin(f1) * Math.cos(f2) * Math.cos(dl));
        var deg = Math.atan2(y, x) * 180.0 / Math.PI;
        return (deg < 0 ? deg + 360.0 : deg).toFloat();
    }

    // Haversine, in metres. Good to a few metres across a city, which is the
    // only range that matters here.
    function metresBetween(fromLat as Float, fromLon as Float,
                           toLat as Float, toLon as Float) as Float {
        var r = 6371000.0;
        var f1 = toRad(fromLat);
        var f2 = toRad(toLat);
        var df = f2 - f1;
        var dl = toRad(toLon - fromLon);

        var sf = Math.sin(df / 2);
        var sl = Math.sin(dl / 2);
        var a = (sf * sf) + (Math.cos(f1) * Math.cos(f2) * sl * sl);
        if (a < 0) { a = 0; }
        if (a > 1) { a = 1; }
        return (2 * r * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))).toFloat();
    }

    // Truncates on a word boundary where it can, with an ellipsis.
    function clip(text as String, max as Number) as String {
        if (text.length() <= max) { return text; }
        var cut = text.substring(0, max - 1) as String;
        var space = lastSpace(cut);
        if (space > max / 2) { cut = cut.substring(0, space) as String; }
        return cut + "...";
    }

    function lastSpace(s as String) as Number {
        for (var i = s.length() - 1; i >= 0; i--) {
            if ((s.substring(i, i + 1) as String).equals(" ")) { return i; }
        }
        return -1;
    }

    function toRad(deg as Float) as Float {
        return (deg * Math.PI / 180.0).toFloat();
    }
}
