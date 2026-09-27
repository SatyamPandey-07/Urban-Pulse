//
// Urban Pulse - entry point.
//
// The watch shows the itinerary the Yatri planner built on the phone. The phone
// publishes the finished plan to the Urban Pulse registry the moment the agents
// are done (PUT /api/watch/<code>); the watch pulls it from the same place
// (GET /api/watch/<code>) on launch, on a START press, and on a temporal event
// while it is closed.
//
// The split is the one the calculator skeleton was built around: TripStore is
// pure logic with no screen, TripClient is the only thing that touches the
// network, and PulseView derives every coordinate from the display size.
//
// One structural rule runs through this class: **this same object is also the
// entry point of the background process**, which gets its own, much smaller
// memory budget and only the classes the service can reach. So initialize()
// and onStart() must touch nothing the UI owns - the store, the client and the
// view are built in getInitialView(), which the background process never calls.
//
import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Storage keys. The payload is cached verbatim so the app opens on the last
// known plan instantly, and keeps working with the phone out of range.
const STORE_TRIP = "trip";
const STORE_AT   = "tripFetchedAt";

class PulseApp extends Application.AppBase {

    private var _store as TripStore or Null;
    private var _client as TripClient or Null;
    private var _view as PulseView or Null;

    private var _code as String;
    private var _server as String;

    function initialize() {
        AppBase.initialize();                    // mandatory super-call
        _store = null;
        _client = null;
        _view = null;
        _code = "";
        _server = "";
    }

    // Runs in the background process too, so: nothing but the schedule.
    function onStart(state as Dictionary?) as Void {
        scheduleBackgroundRefresh();
    }

    function onStop(state as Dictionary?) as Void {
        if (_store == null) { return; }
        var store = _store as TripStore;
        var trip = store.exportTrip();
        if (trip != null) {
            Application.Storage.setValue(STORE_TRIP, trip);
            Application.Storage.setValue(STORE_AT, store.fetchedAt());
        }
    }

    // Returns [view] or [view, delegate]. Left unannotated on purpose: the
    // exact tuple type Garmin expects here has changed across SDK versions.
    // This is also where the UI half of the app comes into existence.
    function getInitialView() {
        loadSettings();

        var store = new TripStore();
        _store = store;
        _client = new TripClient(method(:onFetched));

        var cached = Application.Storage.getValue(STORE_TRIP);
        if (cached instanceof Dictionary) {
            var at = Application.Storage.getValue(STORE_AT);
            store.load(cached as Dictionary, at instanceof Number ? at as Number : 0);
        } else {
            // Debug builds only: a plan to develop the screens against, because
            // no simulator or watch can reach a server on this machine - Connect
            // IQ relays web requests through Garmin (see SamplePlan.mc). In a
            // release build samplePlan() is null and this does nothing.
            // fetchedAt 0: the footer then reads "not synced yet", which is
            // the truth about a fixture.
            store.load(samplePlan(), 0);
        }

        var view = new PulseView(store);
        _view = view;
        // Whatever was cached is shown at once; the plan may have changed since.
        refresh(false);
        return [ view, new PulseDelegate(self, view) ];
    }

    // Called when the user edits the settings in Garmin Connect, or in the
    // simulator's settings editor. A new pairing code means a different trip,
    // so drop the cached one rather than showing someone else's plan.
    function onSettingsChanged() as Void {
        var previous = _code;
        loadSettings();
        if (_store == null) { return; }

        if (!previous.equals(_code)) {
            Application.Storage.deleteValue(STORE_TRIP);
            Application.Storage.deleteValue(STORE_AT);
            var fresh = new TripStore();
            _store = fresh;
            if (_view != null) { (_view as PulseView).attach(fresh); }
        }
        refresh(true);
    }

    // ------------------------------------------------------------------
    // Syncing
    // ------------------------------------------------------------------

    // `manual` marks a START press: it reports failures on screen, where an
    // automatic refresh stays quiet and leaves the cached plan alone.
    function refresh(manual as Boolean) as Void {
        if (_store == null || _client == null) { return; }
        var store = _store as TripStore;
        var client = _client as TripClient;
        if (client.isBusy()) { return; }

        if (_code.length() == 0) {
            store.setError("No pairing code. Set it in Garmin Connect.");
            redraw(false);
            return;
        }

        if (_server.length() == 0) {
            store.setError("No server set. Add it in Garmin Connect.");
            redraw(false);
            return;
        }

        if (manual) { store.setError(null); }
        redraw(client.fetch(_server, _code, store.fetchedAt()));
    }

    function onFetched(outcome as Symbol, payload as Dictionary or Null) as Void {
        if (_store == null) { return; }
        var store = _store as TripStore;

        Fmt.log("sync " + outcome.toString());

        if (outcome == :ok) {
            store.load(payload, Time.now().value());
            store.setError(null);
            Fmt.log("trip: " + store.destination() + ", " + store.dayCount().toString()
                    + " days, " + store.slots(store.dayIndexFor(Time.now().value())).size().toString()
                    + " stops today");
            if (_view != null) { (_view as PulseView).followToday(); }
        } else if (outcome == :unchanged) {
            store.setError(null);
        } else if (outcome == :unpaired) {
            store.setError(store.hasTrip() ? null : "No trip published for " + _code);
        } else if (outcome == :offline) {
            store.setError(store.hasTrip() ? null : "Phone not reachable");
        } else if (outcome == :badData) {
            store.setError("Update the watch app");
        } else {
            store.setError(store.hasTrip() ? null : "Sync failed");
        }
        redraw(false);
    }

    // What the background service handed back after its own fetch. This can
    // arrive before there is any UI, so the cache is written either way.
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (!(data instanceof Dictionary)) { return; }
        if (!TripStore.isUsable(data as Dictionary)) { return; }

        var now = Time.now().value();
        Application.Storage.setValue(STORE_TRIP, data);
        Application.Storage.setValue(STORE_AT, now);

        if (_store != null) {
            (_store as TripStore).load(data as Dictionary, now);
            redraw(false);
        }
    }

    function getServiceDelegate() {
        return [ new BgService() ];
    }

    function pairingCode() as String { return _code; }
    function serverUrl() as String { return _server; }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    private function redraw(syncing as Boolean) as Void {
        if (_view != null) { (_view as PulseView).setSyncing(syncing); }
        WatchUi.requestUpdate();
    }

    private function loadSettings() as Void {
        var code = Application.Properties.getValue("pairingCode");
        _code = code instanceof String ? (code as String).toUpper() : "";

        var server = Application.Properties.getValue("serverUrl");
        _server = server instanceof String ? server as String : "";
    }

    // Every 30 minutes, which is the shortest interval worth spending battery
    // on for a plan that changes when the traveller replans - not by the minute.
    private function scheduleBackgroundRefresh() as Void {
        if (!(System has :ServiceDelegate)) { return; }
        if (Background.getTemporalEventRegisteredTime() != null) { return; }
        Background.registerForTemporalEvent(new Time.Duration(30 * 60));
    }
}
