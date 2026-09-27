//
// BgService - the same fetch, without the app being open.
//
// Connect IQ wakes this up on a temporal event, gives it one HTTP request and a
// few seconds of runtime, then kills it. Whatever it passes to Background.exit()
// is handed to PulseApp.onBackgroundData() the next time the app runs, so the
// itinerary is already on the watch before the traveller raises their wrist.
//
import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

(:background)
class BgService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var code = Application.Properties.getValue("pairingCode");
        var server = Application.Properties.getValue("serverUrl");

        if (!(code instanceof String) || !(server instanceof String)
                || (code as String).length() == 0 || (server as String).length() == 0) {
            Background.exit(null);
            return;
        }

        Communications.makeWebRequest(
            trimSlash(server as String) + "/api/watch/" + (code as String).toUpper(),
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "Accept" => "application/json" },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onReceive)
        );
    }

    function onReceive(responseCode as Number, data as Dictionary or String or Null) as Void {
        // Anything other than a payload we can read: exit empty and leave the
        // cached trip in place.
        if (responseCode == 200 && data instanceof Dictionary && looksLikeATrip(data as Dictionary)) {
            Background.exit(data as Dictionary);
            return;
        }
        Background.exit(null);
    }

    // Deliberately not TripStore.isUsable(): reaching into the model would pull
    // it, and everything it references, into the background memory budget. The
    // app validates properly when it picks the payload up.
    private function looksLikeATrip(payload as Dictionary) as Boolean {
        return payload.get("t") instanceof String && payload.get("d") instanceof Array;
    }

    private function trimSlash(url as String) as String {
        var out = url;
        while (out.length() > 0 && (out.substring(out.length() - 1, out.length()) as String).equals("/")) {
            out = out.substring(0, out.length() - 1) as String;
        }
        return out;
    }
}
