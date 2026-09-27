import Toybox.Lang;
import Toybox.WatchUi;

//! The SOS screen's input.
//!
//! The hold is built from the raw key events rather than `onSelect`, because
//! `onSelect` only fires on release and would make a three-second hold
//! indistinguishable from a tap.
//!
//! BACK means two different things by design: during the phone's cancel window
//! it cancels the SOS, and at any other time it leaves the screen. Leaving a
//! screen must never be the thing that silently cancels an emergency, so while a
//! countdown is running the cancel takes priority and the screen stays put.
class SosDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView;

    //! The view is passed in rather than looked up: a delegate that cannot reach
    //! its view cannot drive the hold, and that would fail silently.
    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onKeyPressed(event) {
        var key = event.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            mView.beginHold();
            return true;
        }
        return false;
    }

    function onKeyReleased(event) {
        var key = event.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            mView.endHold();
            return true;
        }
        return false;
    }

    //! A touch hold, for the same gesture without a button.
    function onHold(event) {
        mView.beginHold();
        return true;
    }

    function onRelease(event) {
        mView.endHold();
        return true;
    }

    function onBack() {
        if (mView.cancelIfCounting()) {
            return true;
        }
        var state = UrbanPulseApp.state;
        if (state != null) {
            state.clearSos();
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    //! `onSelect` fires on release, after the hold has already been handled;
    //! swallowing it stops a tap doing anything at all.
    function onSelect() {
        return true;
    }
}
