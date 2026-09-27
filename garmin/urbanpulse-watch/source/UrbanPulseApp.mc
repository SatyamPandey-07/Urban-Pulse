import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Background;
import Toybox.Time;

//! The Urban Pulse watch companion.
//!
//! It mirrors the phone and does nothing on its own: three features, and each
//! one is either something the phone said or something the traveller pressed.
//!
//!   1. the next stop, its time, and its distance when the phone sends one
//!   2. a buzz and one line of text for a Live Mode update
//!   3. SOS: hold UP/START for three seconds; the phone does the rest
//!
//! Receiving happens two ways, on purpose:
//!   * `Communications.registerForPhoneAppMessages` while the app is on screen;
//!   * `Background.registerForPhoneAppMessageEvent` so an alert still arrives
//!     when it is not. See garmin/README.md for what the fr965 actually allows.
(:glance)
class UrbanPulseApp extends Application.AppBase {

    //! The shared model. Views read it; only this class writes it.
    static var state = null;

    hidden var mHomeView = null;

    function initialize() {
        AppBase.initialize();
        state = new LinkState();
    }

    function onStart(stateDict) {
        // Anything the background service stored while we were closed.
        drainStoredAlert();

        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }
        // Ask the system to wake us for phone messages while the app is closed.
        // Wrapped: a device without the Background permission granted throws
        // here, and that must not stop the foreground half from working.
        if (Background has :registerForPhoneAppMessageEvent) {
            try {
                Background.registerForPhoneAppMessageEvent();
            } catch (e) {
                System.println("background phone events unavailable: " + e.getErrorMessage());
            }
        }
        sayHello();
    }

    function onStop(stateDict) {
    }

    function getInitialView() {
        mHomeView = new HomeView();
        return [mHomeView, new HomeDelegate()];
    }

    //! The glance, so the next stop is visible from the watch face carousel.
    (:glance)
    function getGlanceView() {
        return [new GlanceView()];
    }

    //! Tells the phone we are here, which is what makes the phone's status row
    //! read "Connected" rather than "Watch app not installed".
    function sayHello() {
        var device = "unknown";
        var settings = System.getDeviceSettings();
        if (settings != null && settings has :partNumber && settings.partNumber != null) {
            device = settings.partNumber;
        }
        // Kept in step with the manifest by hand; there is no API that reports
        // the app's own version string.
        transmit(Protocol.hello(device, "1.0.0"));
    }

    //! Sends one protocol message. Failures are logged, not surfaced as success.
    function transmit(payload) {
        if (!(Communications has :transmit)) {
            return;
        }
        try {
            Communications.transmit(payload, null, new TransmitListener());
        } catch (e) {
            System.println("transmit failed: " + e.getErrorMessage());
        }
    }

    //! A message from the phone, while the app is on screen.
    function onPhoneMessage(message as Communications.PhoneAppMessage) as Void {
        handle(message.data);
    }

    //! The single entry point for an inbound payload, wherever it came from.
    //! Returns the `t` it handled, or null when it ignored the message.
    function handle(data) {
        var type = Protocol.typeOf(data);
        // Unknown `t`, a missing `v`, or a newer protocol: ignored in silence.
        if (type == null) {
            return null;
        }
        state.phoneConnected = true;

        if (type.equals("state")) {
            state.applyState(data);
            WatchUi.requestUpdate();
            return type;
        }
        if (type.equals("alert")) {
            var isNew = state.applyAlert(data);
            // Acknowledge even a repeat: the phone's copy of "what the watch has
            // seen" should include it either way.
            var id = Protocol.str(data, "id");
            if (id != null) {
                transmit(Protocol.ack(id));
            }
            if (isNew) {
                Buzz.forAlert(state.alertKind);
                pushAlertView();
            }
            return type;
        }
        if (type.equals("sosAck")) {
            if (state.applySosAck(data)) {
                WatchUi.requestUpdate();
            }
            return type;
        }
        if (type.equals("ping")) {
            Buzz.forAlert(null);
            return type;
        }
        return null;
    }

    //! Raises the alert screen over whatever is showing.
    hidden function pushAlertView() {
        try {
            WatchUi.pushView(new AlertView(), new AlertDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } catch (e) {
            // Pushing a view fails if the app is not in the foreground; the text
            // is already in `state`, so Home shows it on next open.
            System.println("alert view not pushed: " + e.getErrorMessage());
        }
    }

    //! An alert the background service stored while the app was closed.
    function drainStoredAlert() {
        var stored = Application.Storage.getValue(BgService.STORED_ALERT);
        if (stored == null) {
            return;
        }
        Application.Storage.deleteValue(BgService.STORED_ALERT);
        if (Protocol.typeOf(stored) != null) {
            state.applyAlert(stored);
        }
    }

    //! Background wake-up result, delivered when the service exits.
    function onBackgroundData(data) {
        if (data == null) {
            return;
        }
        handle(data);
    }

    function getServiceDelegate() {
        return [new BgService()];
    }
}

//! Logs the real outcome of a transmit. Nothing in the UI claims a message was
//! delivered, so this only needs to leave a trace for the simulator console.
class TransmitListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() {
        System.println("transmit ok");
    }

    function onError() {
        System.println("transmit error");
        if (UrbanPulseApp.state != null) {
            UrbanPulseApp.state.phoneConnected = false;
            WatchUi.requestUpdate();
        }
    }
}

//! Convenience for the views and delegates.
function app() {
    return Application.getApp();
}
