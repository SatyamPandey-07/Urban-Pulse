import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Home's input, by button or by touch.
//!
//! The fr965 has both, and a traveller uses whichever hand is free, so every
//! action here is reachable either way:
//!
//!   START / tap the lower band  open SOS (the 3 second hold happens there, so
//!                               neither a press nor a tap can send anything)
//!   DOWN / tap elsewhere /      open the day's plan
//!   swipe up
//!   MENU                        re-open the last alert, else SOS
//!
//! The SOS tap target is the bottom band because that is where the screen says
//! "SOS": a tap should do what the words under the finger say.
class HomeDelegate extends WatchUi.BehaviorDelegate {

    //! Fraction of the screen height, measured from the bottom, that opens SOS.
    hidden const SOS_BAND = 0.28;

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! START / ENTER: open the SOS screen.
    function onSelect() {
        openSos();
        return true;
    }

    //! DOWN, and the scroll wheel: step into the day's plan.
    function onNextPage() {
        openPlan();
        return true;
    }

    //! A touch. The lower band is SOS, everywhere else is the plan.
    function onTap(event) {
        var coords = event.getCoordinates();
        var height = screenHeight();
        if (coords != null && height > 0 && coords[1] > height * (1.0 - SOS_BAND)) {
            openSos();
            return true;
        }
        openPlan();
        return true;
    }

    //! Swiping up reveals the plan, matching the DOWN key.
    function onSwipe(event) {
        if (event.getDirection() == WatchUi.SWIPE_UP) {
            openPlan();
            return true;
        }
        return false;
    }

    //! Long UP on the fr965. Re-opens an alert that was dismissed or that
    //! arrived while the app was closed; otherwise a second way to SOS.
    function onMenu() {
        var state = UrbanPulseApp.state;
        if (state != null && state.alertText != null) {
            WatchUi.pushView(new AlertView(), new AlertDelegate(), WatchUi.SLIDE_IMMEDIATE);
            return true;
        }
        openSos();
        return true;
    }

    hidden function screenHeight() {
        var settings = System.getDeviceSettings();
        if (settings == null || !(settings has :screenHeight)) {
            return 0;
        }
        return settings.screenHeight;
    }

    hidden function openSos() {
        var view = new SosView();
        WatchUi.pushView(view, new SosDelegate(view), WatchUi.SLIDE_LEFT);
    }

    //! Opens the plan at the step that is happening now, not at the top: the
    //! traveller almost always wants "what next", and scrolling up to this
    //! morning is work they did not ask for.
    hidden function openPlan() {
        var state = UrbanPulseApp.state;
        var start = (state == null) ? 0 : state.currentStepIndex();
        var view = new PlanView(start);
        WatchUi.pushView(view, new PlanDelegate(view), WatchUi.SLIDE_UP);
    }
}
