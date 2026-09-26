//
// CalcDelegate - all input, in one class.
//
// Extending BehaviorDelegate gives both layers at once: the intent callbacks
// (onSelect / onBack / onMenu / onNextPage / onPreviousPage) and the raw touch
// callbacks inherited from InputDelegate. Touch is the primary path; the five
// buttons are a complete fallback for wet hands, gloves and locked screens.
//
import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class CalcDelegate extends WatchUi.BehaviorDelegate {

    private var _engine as CalcEngine;
    private var _view as CalcView;

    function initialize(engine as CalcEngine, view as CalcView) {
        BehaviorDelegate.initialize();
        _engine = engine;
        _view = view;
    }

    // ---- touch: the primary path -------------------------------------

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        var key = _view.keyAt(c[0] as Number, c[1] as Number);
        if (key == null) { return false; }
        hit(key as Symbol);
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_LEFT)  { _view.nextPage(); }
        if (d == WatchUi.SWIPE_RIGHT) { _view.prevPage(); }
        WatchUi.requestUpdate();
        return true;
    }

    // ---- buttons: the fallback path ----------------------------------

    // DOWN / UP walk the keypad cursor.
    function onNextPage() as Boolean {
        _view.moveCursor(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.moveCursor(-1);
        WatchUi.requestUpdate();
        return true;
    }

    // A screen tap and a START press both arrive here first, as the "select"
    // behavior - and this handler has no coordinates. Returning true would tell
    // the system the event is handled and the tap would never reach onTap(),
    // which is exactly the bug that made every tap buzz and insert nothing.
    // So: always defer. Taps fall through to onTap(), the START button falls
    // through to onKey() below.
    function onSelect() as Boolean {
        return false;
    }

    // The physical START button, which never produces a tap event. First press
    // lights the key cursor; after that it presses whatever is highlighted.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            var key = _view.cursorKey();
            if (key == null) {
                _view.moveCursor(1);
                WatchUi.requestUpdate();
                return true;
            }
            hit(key as Symbol);
            return true;
        }
        return false;
    }

    // BACK deletes, and only exits the app when there is nothing left to delete -
    // which is how every native Garmin screen behaves.
    function onBack() as Boolean {
        if (_engine.hasEntry()) {
            hit(:backspace);
            return true;
        }
        return false;
    }

    // On a five-button watch there is no menu key: MENU is a long press of UP.
    function onMenu() as Boolean {
        WatchUi.pushView(buildSettingsMenu(_engine),
                         new SettingsDelegate(_engine),
                         WatchUi.SLIDE_UP);
        return true;
    }

    // ---- shared ------------------------------------------------------

    private function hit(key as Symbol) as Void {
        _engine.press(key);
        if (key == :degrad) {
            // Keep the keypad toggle and the Garmin Connect setting in sync.
            Application.Properties.setValue("degrees", _engine.isDegrees());
        }
        _view.flashKey(key);
        feedback();
        WatchUi.requestUpdate();
    }

    private function feedback() as Void {
        if (!_engine.hapticsOn()) { return; }
        if (Attention has :vibrate && System.getDeviceSettings().vibrateOn) {
            Attention.vibrate([ new Attention.VibeProfile(25, 40) ]);
        }
    }
}
