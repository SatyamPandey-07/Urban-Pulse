//
// A plan to develop against, in debug builds only.
//
// `makeWebRequest` is relayed by Garmin's servers, not sent from the watch, so
// no device or simulator can ever reach a server on the development machine -
// the endpoint has to be publicly reachable over HTTPS. That would make the
// whole UI undevelopable in the simulator, which is what this is for: a debug
// build with no pairing code set loads the payload below instead of syncing.
//
// It is the same shape and the same trip as the phone-side fixture in
// test/fixtures/demo_itinerary.dart, anchored to today so "now" and "next" are
// live, and the (:release) half compiles to nothing on a real build.
//
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:release)
function samplePlan() as Dictionary or Null {
    return null;
}

(:debug)
function samplePlan() as Dictionary or Null {
    var midnight = todayAt(0, 0);

    return {
        "v" => 1,
        "t" => "Rishikesh",
        "o" => "Delhi",
        "dr" => dateRange(),
        "hn" => "Ganga View Homestay",
        "b" => 22280,
        "bx" => 30000,
        "co2" => 38,
        "u" => midnight,
        "d" => [
            {
                "n" => 1, "dt" => dayLabel(0), "w" => "31 degC, 20% rain",
                "sl" => [
                    slot("transit", 0,  6, 50, 11, 50, "Train to Rishikesh", 1740, 30.1087, 78.2932),
                    slot("stay",    0, 12, 30, 13, 30, "Check in - Ganga View Homestay", 0, 30.1068, 78.2947),
                    slot("meal",    0, 13, 30, 14, 30, "Lunch at Chotiwala", 620, 30.1246, 78.3197),
                    slot("visit",   0, 17,  0, 18, 30, "Ganga Aarti at Triveni Ghat", 0, 30.1087, 78.2932),
                    slot("rest",    0, 20,  0, 21,  0, "Dinner at the homestay", 450, 0.0, 0.0)
                ]
            },
            {
                "n" => 2, "dt" => dayLabel(1), "w" => "29 degC, clear",
                "sl" => [
                    slot("meal",    1,  8,  0,  8, 45, "Breakfast", 300, 0.0, 0.0),
                    slot("transit", 1,  9,  0, 10,  0, "Shared taxi to Neelkanth", 900, 30.1571, 78.3888),
                    slot("visit",   1, 10,  0, 12,  0, "Neelkanth Mahadev Temple", 0, 30.1571, 78.3888),
                    slot("meal",    1, 13,  0, 14,  0, "Lunch at Beatles Cafe", 700, 30.1284, 78.3237),
                    slot("visit",   1, 15, 30, 17,  0, "Laxman Jhula and the market", 0, 30.1276, 78.3212)
                ]
            },
            {
                "n" => 3, "dt" => dayLabel(2),
                "sl" => [
                    slot("visit",   2,  7, 30, 10,  0, "Rafting, Shivpuri to Rishikesh", 2400, 30.1428, 78.3765),
                    slot("stay",    2, 11,  0, 11, 30, "Check out", 0, 30.1068, 78.2947),
                    slot("transit", 2, 13,  0, 18, 30, "Train back to Delhi", 1740, 30.1087, 78.2932)
                ]
            }
        ]
    };
}

(:debug)
function slot(kind as String, dayOffset as Number,
              fromHour as Number, fromMinute as Number,
              toHour as Number, toMinute as Number,
              title as String, cost as Number,
              lat as Float, lon as Float) as Dictionary {
    var out = {
        "k" => kind,
        "hm" => clock(fromHour, fromMinute),
        "he" => clock(toHour, toMinute),
        "a" => todayAt(0, 0) + (dayOffset * 86400) + (fromHour * 3600) + (fromMinute * 60),
        "z" => todayAt(0, 0) + (dayOffset * 86400) + (toHour * 3600) + (toMinute * 60),
        "ti" => title
    };
    if (cost > 0) { out.put("c", cost); }
    if (lat != 0.0) { out.put("la", lat); out.put("ln", lon); }
    return out;
}

(:debug)
function clock(hour as Number, minute as Number) as String {
    return (hour < 10 ? "0" : "") + hour.toString() + ":" + (minute < 10 ? "0" : "") + minute.toString();
}

// Local midnight today, as epoch seconds.
(:debug)
function todayAt(hour as Number, minute as Number) as Number {
    var now = Time.now();
    var info = Gregorian.info(now, Time.FORMAT_SHORT);
    var secondsIntoDay = (info.hour * 3600) + (info.min * 60) + info.sec;
    return now.value() - secondsIntoDay + (hour * 3600) + (minute * 60);
}

// "27 Sep - 29 Sep 2026", derived from the same anchor as the days.
(:debug)
function dateRange() as String {
    var first = Gregorian.info(new Time.Moment(todayAt(0, 0)), Time.FORMAT_MEDIUM);
    var last = Gregorian.info(new Time.Moment(todayAt(0, 0) + (2 * 86400)), Time.FORMAT_MEDIUM);
    return first.day.toString() + " " + (first.month as String) + " - "
         + last.day.toString() + " " + (last.month as String) + " " + last.year.toString();
}

(:debug)
function dayLabel(dayOffset as Number) as String {
    var moment = new Time.Moment(todayAt(0, 0) + (dayOffset * 86400));
    var info = Gregorian.info(moment, Time.FORMAT_MEDIUM);
    return (info.day_of_week as String) + " " + info.day.toString() + " " + (info.month as String);
}
