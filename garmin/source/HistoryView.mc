//
// The last dozen calculations, newest first. Persisted across launches by the
// application object via Application.Storage.
//
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class HistoryView extends WatchUi.View {

    private var _engine as CalcEngine;

    function initialize(engine as CalcEngine) {
        View.initialize();
        _engine = engine;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COL_BG, COL_BG);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(COL_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.13).toNumber(), Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.HistoryTitle) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var lines = _engine.getHistory();

        if (lines.size() == 0) {
            dc.setColor(COL_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Graphics.FONT_XTINY,
                        WatchUi.loadResource(Rez.Strings.HistoryEmpty) as String,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Six rows fit inside the circle without touching the bezel.
        var top = (h * 0.26).toNumber();
        var step = (h * 0.105).toNumber();
        var maxW = (w * 0.72).toNumber();

        for (var i = 0; i < lines.size() && i < 6; i++) {
            var text = lines[i] as String;
            while (text.length() > 1
                   && dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > maxW) {
                text = text.substring(1, text.length()) as String;
            }
            dc.setColor(i == 0 ? COL_TEXT : COL_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, top + (i * step), Graphics.FONT_XTINY, text,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}

class HistoryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
