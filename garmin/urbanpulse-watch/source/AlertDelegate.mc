import Toybox.Lang;
import Toybox.WatchUi;

//! The alert screen's input: any of the obvious ways out dismisses it.
class AlertDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() {
        dismiss();
        return true;
    }

    function onSelect() {
        dismiss();
        return true;
    }

    function onTap(event) {
        dismiss();
        return true;
    }

    hidden function dismiss() {
        var state = UrbanPulseApp.state;
        if (state != null) {
            state.clearAlert();
        }
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}
