//
// TripClient - the one place that talks to the network.
//
// One GET against the Urban Pulse registry, decoded straight into a Dictionary
// by the system JSON parser. The phone app publishes the trip to the same
// server (PUT /api/watch/<code>), so the watch never has to talk to the phone
// app directly and needs no companion SDK on either side.
//
//   GET /api/watch/<code>?since=<epoch>
//     200 -> the trip payload
//     204 -> nothing has changed since <epoch>; keep the cached copy
//     404 -> that pairing code has never published a trip
//
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

class TripClient {

    // Handed back to the caller instead of an HTTP code, so the view has one
    // small set of outcomes to draw: :ok, :unchanged, :unpaired, :offline,
    // :badData, :failed.
    private var _onDone as Method(outcome as Symbol, payload as Dictionary or Null) as Void;
    private var _busy as Boolean;

    function initialize(onDone as Method(outcome as Symbol, payload as Dictionary or Null) as Void) {
        _onDone = onDone;
        _busy = false;
    }

    function isBusy() as Boolean { return _busy; }

    // Returns false when the request could not even be started, in which case
    // no callback will arrive.
    function fetch(server as String, code as String, since as Number) as Boolean {
        if (_busy) { return false; }
        if (code.length() == 0 || server.length() == 0) {
            _onDone.invoke(:unpaired, null);
            return false;
        }
        if (!(Communications has :makeWebRequest)) { return false; }

        var settings = System.getDeviceSettings();
        if (settings has :phoneConnected && !settings.phoneConnected) {
            _onDone.invoke(:offline, null);
            return false;
        }

        _busy = true;
        Communications.makeWebRequest(
            trimSlash(server) + "/api/watch/" + code,
            { "since" => since.toString() },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "Accept" => "application/json" },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
        return true;
    }

    function onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        _busy = false;

        if (responseCode == 200) {
            if (data instanceof Dictionary && TripStore.isUsable(data as Dictionary)) {
                _onDone.invoke(:ok, data as Dictionary);
            } else {
                _onDone.invoke(:badData, null);
            }
            return;
        }

        if (responseCode == 204 || responseCode == 304) {
            _onDone.invoke(:unchanged, null);
        } else if (responseCode == 404) {
            _onDone.invoke(:unpaired, null);
        } else if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE
                || responseCode == Communications.BLE_HOST_TIMEOUT
                || responseCode == Communications.NETWORK_REQUEST_TIMED_OUT
                || responseCode == Communications.UNABLE_TO_PROCESS_MEDIA) {
            _onDone.invoke(:offline, null);
        } else {
            _onDone.invoke(:failed, null);
        }
    }

    static function trimSlash(url as String) as String {
        var out = url;
        while (out.length() > 0 && (out.substring(out.length() - 1, out.length()) as String).equals("/")) {
            out = out.substring(0, out.length() - 1) as String;
        }
        return out;
    }
}
