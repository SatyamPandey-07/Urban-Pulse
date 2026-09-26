//
// The settings screen, built with the native Menu2 controls so it looks and
// behaves like the rest of the watch. Reached with a long press of UP.
//
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

function buildSettingsMenu(engine as CalcEngine) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.SettingsTitle) });

    menu.addItem(new WatchUi.ToggleMenuItem(
        WatchUi.loadResource(Rez.Strings.SettingAngle) as String,
        { :enabled => "Degrees", :disabled => "Radians" },
        :angle,
        engine.isDegrees(),
        null));

    menu.addItem(new WatchUi.ToggleMenuItem(
        WatchUi.loadResource(Rez.Strings.SettingHaptics) as String,
        null,
        :haptics,
        engine.hapticsOn(),
        null));

    menu.addItem(new WatchUi.MenuItem(
        WatchUi.loadResource(Rez.Strings.SettingHistory) as String,
        null,
        :history,
        null));

    return menu;
}

class SettingsDelegate extends WatchUi.Menu2InputDelegate {

    private var _engine as CalcEngine;

    function initialize(engine as CalcEngine) {
        Menu2InputDelegate.initialize();
        _engine = engine;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :angle) {
            var on = (item as WatchUi.ToggleMenuItem).isEnabled();
            _engine.setDegrees(on);
            Application.Properties.setValue("degrees", on);

        } else if (id == :haptics) {
            var vibe = (item as WatchUi.ToggleMenuItem).isEnabled();
            _engine.setHaptics(vibe);
            Application.Properties.setValue("haptics", vibe);

        } else if (id == :history) {
            WatchUi.pushView(new HistoryView(_engine), new HistoryDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
