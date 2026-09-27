import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;

//! The glance: the next stop from the watch face carousel, without opening the
//! app. Same honesty rules as Home - nothing received means it says so.
(:glance)
class GlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var state = UrbanPulseApp.state;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (state == null || state.isWaiting() || state.nextTitle == null) {
            dc.drawText(0, h / 2, Graphics.FONT_TINY, "Urban Pulse - no plan",
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        if (state.isStale()) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        }
        var line = state.nextTitle;
        if (state.nextAt != null) {
            line = state.nextAt + "  " + line;
        }
        dc.drawText(0, h / 2, Graphics.FONT_TINY,
                    Protocol.truncate(line, 28),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // `w` is unused for a left-justified single line; kept for symmetry with
        // the other views' signatures.
        if (w < 0) { return; }
    }
}
