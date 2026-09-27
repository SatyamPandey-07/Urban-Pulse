import Toybox.Lang;
import Toybox.WatchUi;

//! Home's input.
//!
//!   START  opens SOS (the 3 second hold happens there, so a press is safe)
//!   DOWN   opens the day's plan
//!   MENU   re-opens the last alert, or SOS when there is none
class HomeDelegate extends WatchUi.BehaviorDelegate {

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

    //! Swiping up from Home reveals the plan, matching the DOWN key.
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

    hidden function openSos() {
        var view = new SosView();
        WatchUi.pushView(view, new SosDelegate(view), WatchUi.SLIDE_LEFT);
    }

    //! Opens the plan at the step that is happening now, not at the top: the
    //! traveller almost always wants "what next", and scrolling up to yesterday
    //! morning is work they did not ask for.
    hidden function openPlan() {
        var state = UrbanPulseApp.state;
        var start = (state == null) ? 0 : state.currentStepIndex();
        var view = new PlanView(start);
        WatchUi.pushView(view, new PlanDelegate(view), WatchUi.SLIDE_UP);
    }
}
