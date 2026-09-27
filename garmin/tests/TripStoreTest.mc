//
// Run No Evil tests for the pure core: the trip model and the formatters.
//
// These run in the simulator only and are stripped from release builds, so they
// cost nothing on the watch. Neither TripStore nor Fmt touches a Dc, the
// network or Storage, which is what makes all of this testable in the first
// place.
//
//   Test Explorer in VS Code (the flask icon), or:
//   ./build.sh test
//
import Toybox.Lang;
import Toybox.Test;

// A two-day trip on a made-up clock: day 1 runs 1000-4000, day 2 90000-91000.
function fixture() as Dictionary {
    return {
        "v" => 1,
        "t" => "Rishikesh",
        "o" => "Delhi",
        "dr" => "24 - 28 Sep 2026",
        "hn" => "Ganga View Homestay",
        "b" => 42000,
        "bx" => 50000,
        "co2" => 38,
        "u" => 900,
        "d" => [
            {
                "n" => 1, "dt" => "Fri 25 Sep", "w" => "31C, 20% rain",
                "sl" => [
                    { "k" => "visit", "hm" => "09:00", "a" => 1000, "z" => 2000,
                      "ti" => "Triveni Ghat", "c" => 0, "la" => 30.1087, "ln" => 78.2932 },
                    { "k" => "meal", "hm" => "11:00", "a" => 3000, "z" => 4000,
                      "ti" => "Lunch at Chotiwala", "c" => 600 }
                ]
            },
            {
                "n" => 2, "dt" => "Sat 26 Sep",
                "sl" => [
                    { "k" => "transit", "hm" => "08:30", "a" => 90000, "z" => 91000,
                      "ti" => "Bus to Neelkanth", "fl" => "Needs confirmation" }
                ]
            }
        ]
    };
}

function loaded() as TripStore {
    var store = new TripStore();
    store.load(fixture(), 950);
    return store;
}

// ---- payload validation ---------------------------------------------------

(:test)
function testAcceptsTheFixture(logger as Logger) as Boolean {
    return TripStore.isUsable(fixture());
}

(:test)
function testRejectsRubbish(logger as Logger) as Boolean {
    return !TripStore.isUsable(null)
        && !TripStore.isUsable({ "d" => [] })            // no destination
        && !TripStore.isUsable({ "t" => "X" });          // no days
}

(:test)
function testRejectsAFuturePayloadVersion(logger as Logger) as Boolean {
    // A newer phone build must not be half-read by an older watch build.
    return !TripStore.isUsable({ "v" => 99, "t" => "X", "d" => [] });
}

(:test)
function testABadPayloadKeepsTheTripAlreadyLoaded(logger as Logger) as Boolean {
    var store = loaded();
    var rejected = !store.load({ "nonsense" => true }, 9999);
    return rejected && store.destination().equals("Rishikesh") && store.fetchedAt() == 950;
}

// ---- reading the trip -----------------------------------------------------

(:test)
function testTripFields(logger as Logger) as Boolean {
    var store = loaded();
    return store.destination().equals("Rishikesh")
        && store.origin().equals("Delhi")
        && store.hotel().equals("Ganga View Homestay")
        && store.budgetInr() == 42000
        && store.budgetMaxInr() == 50000
        && store.co2Kg() == 38
        && store.dayCount() == 2;
}

(:test)
function testSlotsAndBounds(logger as Logger) as Boolean {
    var store = loaded();
    var slot = store.slot(0, 1);
    return store.slots(0).size() == 2
        && store.slots(1).size() == 1
        && store.slots(7).size() == 0              // a day that does not exist
        && slot != null
        && TripStore.text(slot, "ti", "").equals("Lunch at Chotiwala")
        && store.slot(0, 9) == null;
}

(:test)
function testTripStartAndEnd(logger as Logger) as Boolean {
    var store = loaded();
    return store.tripStart() == 1000 && store.tripEnd() == 91000;
}

// ---- where the traveller is ----------------------------------------------

(:test)
function testState(logger as Logger) as Boolean {
    var store = loaded();
    return store.state(500) == :before
        && store.state(1500) == :during
        && store.state(99999) == :after
        && new TripStore().state(1500) == :empty;
}

(:test)
function testCurrentSlotOnlyInsideASlot(logger as Logger) as Boolean {
    var store = loaded();
    var inside = store.currentSlot(1500);
    logger.debug("at 1500: day " + (inside[0] as Number).toString()
                 + " slot " + (inside[1] as Number).toString());
    return (inside[0] as Number) == 0 && (inside[1] as Number) == 0
        && store.currentSlot(2500) == null            // between two slots
        && store.currentSlot(500) == null;            // before the trip
}

(:test)
function testNextSlotSkipsWhatHasStarted(logger as Logger) as Boolean {
    var store = loaded();
    var next = store.nextSlot(1500);                  // inside slot 1 already
    var across = store.nextSlot(5000);                // day 1 is over
    return (next[0] as Number) == 0 && (next[1] as Number) == 1
        && (across[0] as Number) == 1 && (across[1] as Number) == 0
        && store.nextSlot(99999) == null;
}

(:test)
function testDayIndexFollowsTheClock(logger as Logger) as Boolean {
    var store = loaded();
    return store.dayIndexFor(500) == 0               // before the trip
        && store.dayIndexFor(1500) == 0              // mid day 1
        && store.dayIndexFor(5000) == 1              // day 1 finished
        && store.dayIndexFor(99999) == 1;            // after the trip, clamped
}

// ---- typed reads over untrusted data -------------------------------------

(:test)
function testTypedReadsFallBack(logger as Logger) as Boolean {
    var wrong = { "a" => "not a number", "b" => 7, "c" => 2.5 };
    return TripStore.count(wrong, "a", -1) == -1
        && TripStore.count(wrong, "b", -1) == 7
        && TripStore.count(wrong, "c", -1) == 2       // a float truncates
        && TripStore.count(null, "b", -1) == -1
        && TripStore.text(wrong, "b", "fb").equals("fb")
        && TripStore.text(wrong, "missing", "fb").equals("fb");
}

(:test)
function testPositionIsOptional(logger as Logger) as Boolean {
    var store = loaded();
    var withPos = TripStore.position(store.slot(0, 0));
    var without = TripStore.position(store.slot(0, 1));
    return without == null
        && withPos != null
        && ((withPos[0] as Float) - 30.1087).abs() < 0.0001
        && TripStore.position({ "la" => "x", "ln" => 1 }) == null;
}

// ---- formatting ----------------------------------------------------------

(:test)
function testGrouping(logger as Logger) as Boolean {
    return Fmt.grouped(0).equals("0")
        && Fmt.grouped(999).equals("999")
        && Fmt.grouped(1000).equals("1,000")
        && Fmt.grouped(42000).equals("42,000")
        && Fmt.grouped(1234567).equals("1,234,567")
        && Fmt.money(42000).equals("Rs 42,000");
}

(:test)
function testSpan(logger as Logger) as Boolean {
    logger.debug("8100s = " + Fmt.span(8100));
    return Fmt.span(30).equals("<1 min")
        && Fmt.span(45 * 60).equals("45 min")
        && Fmt.span(2 * 3600).equals("2 h")
        && Fmt.span(8100).equals("2 h 15")
        && Fmt.span(3 * 86400).equals("3 d")
        && Fmt.span(-600).equals("10 min");           // sign is the caller's job
}

(:test)
function testDistance(logger as Logger) as Boolean {
    return Fmt.distance(340.0, true).equals("340 m")
        && Fmt.distance(1230.0, true).equals("1.2 km")
        && Fmt.distance(4828.0, false).equals("3.0 mi");
}

(:test)
function testCompassPoints(logger as Logger) as Boolean {
    return Fmt.compass(0.0).equals("N")
        && Fmt.compass(44.0).equals("NE")
        && Fmt.compass(180.0).equals("S")
        && Fmt.compass(350.0).equals("N")
        && Fmt.compass(-10.0).equals("N");
}

(:test)
function testBearingAndDistanceAgree(logger as Logger) as Boolean {
    // Due north, one degree of latitude: ~111 km, bearing 0.
    var metres = Fmt.metresBetween(30.0, 78.0, 31.0, 78.0);
    var bearing = Fmt.bearingBetween(30.0, 78.0, 31.0, 78.0);
    logger.debug("1 deg lat = " + metres.format("%.0f") + " m at " + bearing.format("%.1f"));
    return metres > 110000 && metres < 112000
        && Fmt.compass(bearing).equals("N")
        && Fmt.compass(Fmt.bearingBetween(30.0, 78.0, 30.0, 79.0)).equals("E");
}

(:test)
function testClipPrefersAWordBoundary(logger as Logger) as Boolean {
    logger.debug(Fmt.clip("Triveni Ghat evening aarti", 18));
    return Fmt.clip("Short", 18).equals("Short")
        && Fmt.clip("Triveni Ghat evening aarti", 18).equals("Triveni Ghat...")
        && Fmt.clip("Unbrokenstringofcharacters", 12).length() <= 15;
}
