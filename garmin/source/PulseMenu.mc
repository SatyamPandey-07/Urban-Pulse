//
// The menu behind a long press of UP: the two actions worth a second route,
// and the pairing code - which is the one thing a traveller needs to read off
// the watch when the phone says the two are not paired.
//
import Toybox.Lang;
import Toybox.WatchUi;

function buildPulseMenu(app as PulseApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => Rez.Strings.AppName });

    menu.addItem(new WatchUi.MenuItem(
        WatchUi.loadResource(Rez.Strings.MenuSync) as String,
        WatchUi.loadResource(Rez.Strings.MenuSyncSub) as String,
        :sync, {}));

    menu.addItem(new WatchUi.MenuItem(
        WatchUi.loadResource(Rez.Strings.MenuToday) as String,
        null, :today, {}));

    var code = app.pairingCode();
    menu.addItem(new WatchUi.MenuItem(
        WatchUi.loadResource(Rez.Strings.MenuCode) as String,
        code.length() == 0 ? WatchUi.loadResource(Rez.Strings.MenuCodeUnset) as String : code,
        :code, {}));

    return menu;
}

class PulseMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _app as PulseApp;
    private var _view as PulseView;

    function initialize(app as PulseApp, view as PulseView) {
        Menu2InputDelegate.initialize();
        _app = app;
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :sync) {
            _app.refresh(true);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :today) {
            _view.followToday();
            _view.setPage(PulseView.PAGE_DAY);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        // The pairing code is there to be read, so selecting it does nothing.
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
