import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Application;

//! The background half of the link.
//!
//! Registered with `Background.registerForPhoneAppMessageEvent`, this is woken
//! by the system when the phone transmits while the app is not on screen. It has
//! a few seconds and a small memory budget, so it does exactly two things:
//!
//!   * buzz, if the message is an alert and the watch's settings allow it — this
//!     is the only part that has to happen now, because a buzz five minutes late
//!     is worse than none;
//!   * store the payload and exit, handing it to the app the next time it opens.
//!
//! `Background.exit` also delivers the payload to `onBackgroundData` if the app
//! happens to be resident, which is why the app's `handle()` is the single entry
//! point for both paths.
//!
//! What this cannot do: show a view. There is no UI from a background service on
//! any device. The buzz is the notification; the text waits for the app.
class BgService extends System.ServiceDelegate {

    //! Storage key for the payload handed forward to the app.
    static const STORED_ALERT = "pendingAlert";

    function initialize() {
        ServiceDelegate.initialize();
    }

    //! A phone message while the app is closed.
    function onPhoneAppMessage(message) {
        var data = message.data;
        var type = Protocol.typeOf(data);
        if (type == null) {
            // Not our protocol version: exit without waking the app.
            Background.exit(null);
            return;
        }

        if (type.equals("alert")) {
            Buzz.forAlert(Protocol.str(data, "kind"));
            // Keep only the newest; a queue would not fit the memory budget and
            // the traveller only needs the current situation.
            Application.Storage.setValue(STORED_ALERT, data);
        } else if (type.equals("ping")) {
            Buzz.forAlert(null);
        } else if (type.equals("sosAck")) {
            // An SOS acknowledgement is worth a buzz only when it is the final
            // word; a per-second countdown would buzz ten times.
            var status = Protocol.str(data, "status");
            if (status != null && !status.equals("countdown")) {
                Buzz.forAlert(Protocol.KIND_ARRIVED);
            }
        }

        Background.exit(data);
    }

    //! Registered only for phone messages, so this should not fire. Exiting
    //! cleanly is still better than being killed by the watchdog.
    function onTemporalEvent() {
        Background.exit(null);
    }
}
