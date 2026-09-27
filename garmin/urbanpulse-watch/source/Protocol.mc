import Toybox.Lang;
import Toybox.System;
import Toybox.Math;

//! The wire format, watch side. Mirrors
//! `urbanpulse_flutter/lib/services/watch/watch_protocol.dart`; change one and
//! change the other.
//!
//! Everything here is defensive. A phone message arrives as whatever the
//! Connect IQ runtime made of it, so each field is checked for both presence and
//! type before it is used: a malformed message must leave the watch showing the
//! last good state, never a crash or a blank screen.
module Protocol {

    //! The only version this app speaks.
    const VERSION = 1;

    //! Longest line the views lay out without clipping on a 454 px round screen.
    const MAX_LINE = 60;

    // Alert kinds, as they appear on the wire.
    const KIND_LEAVE = "leave";
    const KIND_ARRIVED = "arrived";
    const KIND_LATE = "late";
    const KIND_MEAL = "meal";
    const KIND_RAIN = "rain";

    //! True when `data` is a dictionary carrying exactly our protocol version.
    //!
    //! A missing `v`, a string `"1"`, or a newer `2` are all false: an unknown
    //! dialect is silence, not a guess.
    function accepts(data) {
        if (!(data instanceof Lang.Dictionary)) {
            return false;
        }
        var v = data["v"];
        if (!(v instanceof Lang.Number)) {
            return false;
        }
        return v == VERSION;
    }

    //! The `t` of an accepted message, or null.
    function typeOf(data) {
        if (!accepts(data)) {
            return null;
        }
        var t = data["t"];
        return (t instanceof Lang.String) ? t : null;
    }

    //! A string field, or null when absent or of the wrong type.
    function str(data, key) {
        if (!(data instanceof Lang.Dictionary)) {
            return null;
        }
        var value = data[key];
        if (value instanceof Lang.String && value.length() > 0) {
            return value;
        }
        return null;
    }

    //! A whole-number field, or null. Floats are accepted and rounded, because
    //! a distance that arrived as 412.0 is still a distance.
    function num(data, key) {
        if (!(data instanceof Lang.Dictionary)) {
            return null;
        }
        var value = data[key];
        if (value instanceof Lang.Number) {
            return value;
        }
        if (value instanceof Lang.Long) {
            return value.toNumber();
        }
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            return Math.round(value).toNumber();
        }
        return null;
    }

    //! A boolean field, defaulting to `fallback`.
    function bool(data, key, fallback) {
        if (!(data instanceof Lang.Dictionary)) {
            return fallback;
        }
        var value = data[key];
        if (value instanceof Lang.Boolean) {
            return value;
        }
        return fallback;
    }

    //! A dictionary field, or null.
    function dict(data, key) {
        if (!(data instanceof Lang.Dictionary)) {
            return null;
        }
        var value = data[key];
        return (value instanceof Lang.Dictionary) ? value : null;
    }

    //! Reduces `text` to printable ASCII, single-spaced, at most `max` long.
    //!
    //! The phone already does this. The watch does it again because the phone is
    //! not the only thing that can transmit to this app, and a non-ASCII
    //! codepoint draws as a blank box.
    function sanitise(text, max) {
        if (!(text instanceof Lang.String)) {
            return "";
        }
        var chars = text.toCharArray();
        var out = "";
        var lastWasSpace = true; // trims the leading space too
        for (var i = 0; i < chars.size(); i++) {
            var n = chars[i].toNumber();
            var isSpace = (n == 0x20 || n == 0x09 || n == 0x0A || n == 0x0D);
            if (n < 0x20 || n > 0x7E) {
                isSpace = true;
            }
            if (isSpace) {
                if (!lastWasSpace) {
                    out += " ";
                    lastWasSpace = true;
                }
            } else {
                out += chars[i].toString();
                lastWasSpace = false;
            }
        }
        // Drop a trailing space left by the collapse.
        if (out.length() > 0 && out.substring(out.length() - 1, out.length()).equals(" ")) {
            out = out.substring(0, out.length() - 1);
        }
        return truncate(out, max);
    }

    //! Cuts `text` to `max`, on a word boundary where that keeps most of the
    //! budget, marking the cut with "..." so a clipped line reads as clipped.
    function truncate(text, max) {
        if (max <= 0) {
            return "";
        }
        if (text.length() <= max) {
            return text;
        }
        if (max <= 3) {
            return text.substring(0, max);
        }
        var hard = text.substring(0, max - 3);
        var lastSpace = -1;
        var chars = hard.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i].toNumber() == 0x20) {
                lastSpace = i;
            }
        }
        var body = hard;
        if (lastSpace >= (max - 3) / 2) {
            body = hard.substring(0, lastSpace);
        }
        return body + "...";
    }

    //! `{t:"hello", ...}`
    function hello(device, appVersion) {
        return { "t" => "hello", "v" => VERSION, "device" => device, "appVersion" => appVersion };
    }

    //! `{t:"sos", ...}` - epoch seconds, the format the phone parses.
    function sos(epochSeconds) {
        return { "t" => "sos", "v" => VERSION, "ts" => epochSeconds };
    }

    //! `{t:"sosCancel"}`
    function sosCancel() {
        return { "t" => "sosCancel", "v" => VERSION };
    }

    //! `{t:"ack", id:...}` - confirms an alert was put on screen.
    function ack(id) {
        return { "t" => "ack", "v" => VERSION, "id" => id };
    }
}
