import Toybox.Lang;
import Toybox.WatchUi;

//! The plan's input: DOWN and UP step through the day.
//!
//! Both the physical keys and the swipe/scroll gestures are handled, because the
//! fr965 has a touchscreen and buttons and travellers use whichever hand is free.
class PlanDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    //! The DOWN button, and the scroll wheel where there is one.
    function onNextPage() {
        mView.move(1);
        return true;
    }

    //! The UP button.
    function onPreviousPage() {
        mView.move(-1);
        return true;
    }

    //! Swiping up reveals what is further down the list, and vice versa.
    function onSwipe(event) {
        var dir = event.getDirection();
        if (dir == WatchUi.SWIPE_UP) {
            mView.move(1);
            return true;
        }
        if (dir == WatchUi.SWIPE_DOWN) {
            mView.move(-1);
            return true;
        }
        // A left/right swipe falls through to BACK.
        return false;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    //! START on a step does nothing on purpose: there is no action to take here,
    //! and swallowing it stops a stray press opening the SOS screen underneath.
    function onSelect() {
        return true;
    }
}
