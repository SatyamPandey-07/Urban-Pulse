//
// Urban Pulse Calc - entry point.
//
// Today this is a calculator. The structure is the one the Urban Pulse watch
// app will need later: a pure-logic core (CalcEngine) that knows nothing about
// the screen, a view that derives every coordinate from the display size, and
// one delegate for all input. Adding the network layer means adding a client
// class next to CalcEngine and the Communications permission to the manifest -
// no change to the view or the delegate.
//
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class UrbanPulseCalcApp extends Application.AppBase {

    private var _engine as CalcEngine;

    function initialize() {
        AppBase.initialize();            // mandatory super-call
        _engine = new CalcEngine();
    }

    function onStart(state as Dictionary?) as Void {
        loadSettings();

        var saved = Application.Storage.getValue("history");
        if (saved instanceof Array) {
            _engine.restoreHistory(saved as Array);
        }
    }

    function onStop(state as Dictionary?) as Void {
        Application.Storage.setValue("history", _engine.exportHistory());
    }

    // Called when the user edits the settings in Garmin Connect, or in the
    // simulator's settings editor.
    function onSettingsChanged() as Void {
        loadSettings();
        WatchUi.requestUpdate();
    }

    // Returns [view] or [view, delegate]. Left unannotated on purpose: the
    // exact tuple type Garmin expects here has changed across SDK versions.
    function getInitialView() {
        var view = new CalcView(_engine);
        return [ view, new CalcDelegate(_engine, view) ];
    }

    private function loadSettings() as Void {
        var degrees = Application.Properties.getValue("degrees");
        if (degrees != null) { _engine.setDegrees(degrees as Boolean); }

        var haptics = Application.Properties.getValue("haptics");
        if (haptics != null) { _engine.setHaptics(haptics as Boolean); }

        var decimals = Application.Properties.getValue("decimals");
        if (decimals != null) { _engine.setDecimals(decimals as Number); }
    }
}
