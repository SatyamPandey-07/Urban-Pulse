import Toybox.Lang;
import Toybox.WatchUi;

//! Home's input. START opens the SOS screen; MENU brings back the last alert if
//! there is one. A single press never sends anything.
class HomeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! START / ENTER: open the SOS screen. The three-second hold happens there.
    function onSelect() {
        openSos();
        return true;
    }

    //! Long UP on the fr965. Re-opens an alert that was dismissed or that
    //! arrived while the app was closed; otherwise it is a second way to SOS.
    function onMenu() {
        var state = UrbanPulseApp.state;
        if (state != null && state.alertText != null) {
            WatchUi.pushView(new AlertView(), new AlertDelegate(), WatchUi.SLIDE_IMMEDIATE);
            return true;
        }
        openSos();
        return true;
    }

    hidden function openSos() {
        var view = new SosView();
        WatchUi.pushView(view, new SosDelegate(view), WatchUi.SLIDE_LEFT);
    }
}
