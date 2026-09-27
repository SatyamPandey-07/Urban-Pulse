//
// TripStore - the trip, and every question the screens ask about it.
//
// This is the pure core: it holds the decoded payload the phone published and
// answers "what is happening now", "what is next", "which day am I on". It
// touches no Dc and makes no web request, so all of it runs under the unit
// tests in tests/TripStoreTest.mc.
//
// The payload is deliberately tiny and pre-formatted by the phone (see
// lib/services/watch_payload.dart). Short keys, ASCII only, wall-clock times
// already rendered as strings - the watch does no date arithmetic beyond
// comparing epoch seconds:
//
//   { v, t, o, dr, hn, b, bx, co2, u,
//     d: [ { n, dt, w, sl: [ { k, hm, he, a, z, ti, no, c, fl, la, ln } ] } ] }
//
import Toybox.Lang;

// Slot kinds, as the phone spells them.
const KIND_STAY    = "stay";
const KIND_VISIT   = "visit";
const KIND_MEAL    = "meal";
const KIND_TRANSIT = "transit";
const KIND_REST    = "rest";

class TripStore {

    // The payload version this build understands.
    static const VERSION = 1;

    private var _trip as Dictionary or Null;
    private var _fetchedAt as Number;          // epoch seconds of the last good sync
    private var _error as String or Null;

    function initialize() {
        _trip = null;
        _fetchedAt = 0;
        _error = null;
    }

    // ------------------------------------------------------------------
    // Loading
    // ------------------------------------------------------------------

    // Accepts a decoded payload. Returns false - and keeps whatever trip was
    // already loaded - when the payload is not one we can read, so a bad
    // response never blanks a good screen.
    function load(payload as Dictionary or Null, fetchedAt as Number) as Boolean {
        if (!isUsable(payload)) { return false; }
        _trip = payload as Dictionary;
        _fetchedAt = fetchedAt;
        _error = null;
        return true;
    }

    static function isUsable(payload as Dictionary or Null) as Boolean {
        if (!(payload instanceof Dictionary)) { return false; }
        var p = payload as Dictionary;
        if (!(p.get("t") instanceof String)) { return false; }
        if (!(p.get("d") instanceof Array)) { return false; }

        var v = p.get("v");
        // An older phone build is fine; a newer payload shape is not.
        return !(v instanceof Number) || (v as Number) <= VERSION;
    }

    function hasTrip() as Boolean { return _trip != null; }

    function setError(message as String or Null) as Void { _error = message; }
    function getError() as String or Null { return _error; }

    function fetchedAt() as Number { return _fetchedAt; }

    // For Application.Storage: the payload goes back out exactly as it came in.
    function exportTrip() as Dictionary or Null { return _trip; }

    // ------------------------------------------------------------------
    // The trip as a whole
    // ------------------------------------------------------------------

    function destination() as String { return text(_trip, "t", ""); }
    function origin() as String      { return text(_trip, "o", ""); }
    function dateRange() as String   { return text(_trip, "dr", ""); }
    function hotel() as String       { return text(_trip, "hn", ""); }
    function budgetInr() as Number   { return count(_trip, "b", 0); }
    function budgetMaxInr() as Number { return count(_trip, "bx", 0); }
    function co2Kg() as Number       { return count(_trip, "co2", 0); }
    function publishedAt() as Number { return count(_trip, "u", 0); }

    function dayCount() as Number {
        if (_trip == null) { return 0; }
        var days = (_trip as Dictionary).get("d");
        return days instanceof Array ? (days as Array).size() : 0;
    }

    function day(index as Number) as Dictionary or Null {
        if (_trip == null) { return null; }
        var days = (_trip as Dictionary).get("d");
        if (!(days instanceof Array)) { return null; }
        var list = days as Array;
        if (index < 0 || index >= list.size()) { return null; }
        var d = list[index];
        return d instanceof Dictionary ? d as Dictionary : null;
    }

    function slots(dayIndex as Number) as Array {
        var d = day(dayIndex);
        if (d == null) { return []; }
        var sl = d.get("sl");
        return sl instanceof Array ? sl as Array : [];
    }

    function slot(dayIndex as Number, slotIndex as Number) as Dictionary or Null {
        var list = slots(dayIndex);
        if (slotIndex < 0 || slotIndex >= list.size()) { return null; }
        var s = list[slotIndex];
        return s instanceof Dictionary ? s as Dictionary : null;
    }

    // ------------------------------------------------------------------
    // Where the traveller is in the plan
    //
    // Every answer is derived from `now` rather than stored, so the screens
    // stay correct across midnight without anything having to be refreshed.
    // ------------------------------------------------------------------

    function tripStart() as Number {
        var first = slot(0, 0);
        return first == null ? 0 : count(first, "a", 0);
    }

    function tripEnd() as Number {
        var last = dayCount() - 1;
        var list = slots(last);
        if (list.size() == 0) { return 0; }
        var s = list[list.size() - 1];
        return s instanceof Dictionary ? count(s as Dictionary, "z", 0) : 0;
    }

    // :empty before anything is synced, then :before / :during / :after.
    function state(now as Number) as Symbol {
        if (!hasTrip() || dayCount() == 0) { return :empty; }
        if (now < tripStart()) { return :before; }
        if (now > tripEnd()) { return :after; }
        return :during;
    }

    // The slot happening right now as [dayIndex, slotIndex], or null between
    // slots and outside the trip.
    function currentSlot(now as Number) as Array or Null {
        for (var d = 0; d < dayCount(); d++) {
            var list = slots(d);
            for (var i = 0; i < list.size(); i++) {
                var s = list[i];
                if (!(s instanceof Dictionary)) { continue; }
                var from = count(s as Dictionary, "a", 0);
                var to = count(s as Dictionary, "z", 0);
                if (now >= from && now < to) { return [d, i]; }
            }
        }
        return null;
    }

    // The first slot that has not started yet, as [dayIndex, slotIndex].
    function nextSlot(now as Number) as Array or Null {
        for (var d = 0; d < dayCount(); d++) {
            var list = slots(d);
            for (var i = 0; i < list.size(); i++) {
                var s = list[i];
                if (!(s instanceof Dictionary)) { continue; }
                if (count(s as Dictionary, "a", 0) > now) { return [d, i]; }
            }
        }
        return null;
    }

    // The day the traveller is on: the first day that has not finished yet,
    // clamped to the trip. Before the trip that is day 0; after it, the last.
    function dayIndexFor(now as Number) as Number {
        var last = dayCount() - 1;
        if (last < 0) { return 0; }

        for (var d = 0; d <= last; d++) {
            var list = slots(d);
            if (list.size() == 0) { continue; }
            var tail = list[list.size() - 1];
            if (!(tail instanceof Dictionary)) { continue; }
            if (now <= count(tail as Dictionary, "z", 0)) { return d; }
        }
        return last;
    }

    // ------------------------------------------------------------------
    // Typed reads. The payload arrives over the air, so nothing in it is
    // trusted to be the type it ought to be.
    // ------------------------------------------------------------------

    static function text(from as Dictionary or Null, key as String, fallback as String) as String {
        if (!(from instanceof Dictionary)) { return fallback; }
        var v = (from as Dictionary).get(key);
        return v instanceof String ? v as String : fallback;
    }

    static function count(from as Dictionary or Null, key as String, fallback as Number) as Number {
        if (!(from instanceof Dictionary)) { return fallback; }
        var v = (from as Dictionary).get(key);
        if (v instanceof Number) { return v as Number; }
        if (v instanceof Float)  { return (v as Float).toNumber(); }
        if (v instanceof Long)   { return (v as Long).toNumber(); }
        if (v instanceof Double) { return (v as Double).toNumber(); }
        return fallback;
    }

    // Latitude/longitude, or null when the phone had no coordinate for a stop.
    static function position(from as Dictionary or Null) as Array or Null {
        if (!(from instanceof Dictionary)) { return null; }
        var lat = (from as Dictionary).get("la");
        var lon = (from as Dictionary).get("ln");
        if (lat == null || lon == null) { return null; }
        if (!(lat instanceof Number || lat instanceof Float || lat instanceof Double)) { return null; }
        if (!(lon instanceof Number || lon instanceof Float || lon instanceof Double)) { return null; }
        return [ (lat as Numeric).toFloat(), (lon as Numeric).toFloat() ];
    }
}
