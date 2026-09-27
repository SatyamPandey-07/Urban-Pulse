import Toybox.Lang;
import Toybox.System;
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
    //! Swiping right leaves, which is the gesture Garmin users expect for back.
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
        if (dir == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }

    //! A tap pages down, so the whole list can be read by touch alone. Tapping
    //! the top quarter pages back, for a finger that overshot.
    function onTap(event) {
        var coords = event.getCoordinates();
        var settings = System.getDeviceSettings();
        if (coords != null && settings != null && settings has :screenHeight) {
            if (coords[1] < settings.screenHeight * 0.25) {
                mView.move(-1);
                return true;
            }
        }
        mView.move(1);
        return true;
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
