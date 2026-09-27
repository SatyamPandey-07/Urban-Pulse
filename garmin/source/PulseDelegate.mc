//
// PulseDelegate - all input, in one class.
//
// Extending BehaviorDelegate gives both layers at once: the intent callbacks
// (onSelect / onBack / onMenu / onNextPage / onPreviousPage) and the raw touch
// callbacks inherited from InputDelegate. Touch is the primary path; the five
// buttons are a complete fallback for wet hands, gloves and a locked screen.
//
//   swipe left/right   next / previous page
//   UP / DOWN          scroll the day's timeline (rolling into the next day),
//                      or change page on the other two screens
//   START              sync with the phone's plan now
//   tap the day header left / right edge   previous / next day
//   tap anywhere on the first page         sync
//   long-press UP      menu
//
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class PulseDelegate extends WatchUi.BehaviorDelegate {

    private var _app as PulseApp;
    private var _view as PulseView;

    function initialize(app as PulseApp, view as PulseView) {
        BehaviorDelegate.initialize();
        _app = app;
        _view = view;
    }

    // ---- touch: the primary path -------------------------------------

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        var target = _view.hitTest(c[0] as Number, c[1] as Number);

        if (target == :prevDay)      { _view.moveDay(-1); }
        else if (target == :nextDay) { _view.moveDay(1); }
        else if (target == :today)   { _view.followToday(); }
        else if (target == :sync)    { syncNow(); return true; }
        else                         { return false; }

        WatchUi.requestUpdate();
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_LEFT)       { _view.nextPage(); }
        else if (d == WatchUi.SWIPE_RIGHT) { _view.prevPage(); }
        else if (d == WatchUi.SWIPE_UP)    { _view.scrollBy(1); }
        else if (d == WatchUi.SWIPE_DOWN)  { _view.scrollBy(-1); }
        WatchUi.requestUpdate();
        return true;
    }

    // ---- buttons: the fallback path ----------------------------------

    function onNextPage() as Boolean {
        if (_view.page() == PulseView.PAGE_DAY) { _view.scrollBy(1); }
        else                                    { _view.nextPage(); }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view.page() == PulseView.PAGE_DAY) { _view.scrollBy(-1); }
        else                                    { _view.prevPage(); }
        WatchUi.requestUpdate();
        return true;
    }

    // A screen tap and a START press both arrive here first, as the "select"
    // behavior - and this handler has no coordinates. Returning true would tell
    // the system the event is handled and the tap would never reach onTap().
    // So: always defer. Taps fall through to onTap(), START to onKey().
    function onSelect() as Boolean {
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            syncNow();
            return true;
        }
        return false;
    }

    // On a five-button watch there is no menu key: MENU is a long press of UP.
    function onMenu() as Boolean {
        WatchUi.pushView(buildPulseMenu(_app), new PulseMenuDelegate(_app, _view),
                         WatchUi.SLIDE_UP);
        return true;
    }

    // ---- shared ------------------------------------------------------

    private function syncNow() as Void {
        _app.refresh(true);
        if (Attention has :vibrate && System.getDeviceSettings().vibrateOn) {
            Attention.vibrate([ new Attention.VibeProfile(25, 40) ]);
        }
    }
}
