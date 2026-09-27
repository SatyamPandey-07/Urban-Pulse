import Toybox.Lang;
import Toybox.Graphics;
import Toybox.Math;
import Toybox.System;

//! Fitting text to a round screen.
//!
//! The fr965 is a 454 px circle, and that is the whole problem: a line of text
//! near the top or bottom of the screen has far less room than one across the
//! middle, because the usable width at any height is a *chord* of the circle,
//! not the full width. Laying out to `dc.getWidth()` is what makes long place
//! names run off the edge.
//!
//! So everything here works from two ideas:
//!
//!   * [chordWidth] gives the real width available at a given y, inset from the
//!     bezel, so a caller never has to guess;
//!   * [bestFont] picks the largest font from a preference list that actually
//!     fits, instead of committing to one size and hoping.
//!
//! Nothing here hard-codes a pixel: every measurement comes from `dc`, so adding
//! a product to manifest.xml needs no change.
module Layout {

    //! Fraction of the radius kept clear of the curved edge. Round watches put
    //! nothing readable in the last few percent.
    const BEZEL = 0.06;

    //! Font ladders, largest first. `bestFont` walks these until something fits.
    const TITLE_FONTS = [
        Graphics.FONT_LARGE,
        Graphics.FONT_MEDIUM,
        Graphics.FONT_SMALL,
        Graphics.FONT_TINY,
        Graphics.FONT_XTINY
    ];

    const BODY_FONTS = [
        Graphics.FONT_MEDIUM,
        Graphics.FONT_SMALL,
        Graphics.FONT_TINY,
        Graphics.FONT_XTINY
    ];

    const NUMBER_FONTS = [
        Graphics.FONT_NUMBER_MEDIUM,
        Graphics.FONT_NUMBER_MILD,
        Graphics.FONT_MEDIUM,
        Graphics.FONT_SMALL
    ];

    //! The drawable width of the screen at height `y`.
    //!
    //! For a round screen this is the chord `2*sqrt(r^2 - dy^2)`, inset by
    //! [BEZEL]. For a rectangular one it is simply the inset width, which is why
    //! callers can use this unconditionally.
    function chordWidth(dc, y) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (!isRound(dc)) {
            return w * (1.0 - 2 * BEZEL);
        }
        var r = w / 2.0;
        var dy = y - h / 2.0;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) {
            return 0;
        }
        var half = Math.sqrt(r * r - dy * dy);
        return 2 * half * (1.0 - BEZEL * 2);
    }

    //! True when the device screen is a circle.
    function isRound(dc) {
        var settings = System.getDeviceSettings();
        if (settings != null && settings has :screenShape) {
            return settings.screenShape == System.SCREEN_SHAPE_ROUND;
        }
        // No answer: treat a square-ish screen as round, which only ever
        // reserves more margin than needed.
        return dc.getWidth() == dc.getHeight();
    }

    //! The largest font in `fonts` whose rendering of `text` fits `maxWidth`.
    //!
    //! Returns the smallest font when nothing fits; the caller is expected to
    //! wrap or truncate at that point rather than overflow.
    function bestFont(dc, text, fonts, maxWidth) {
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return fonts[fonts.size() - 1];
    }

    //! The largest font that lets `text` wrap into at most `maxLines` lines,
    //! each within the chord at `y`.
    function bestWrappedFont(dc, text, fonts, y, maxLines) {
        for (var i = 0; i < fonts.size(); i++) {
            var lines = wrap(dc, text, fonts[i], chordWidth(dc, y));
            if (lines.size() <= maxLines) {
                return fonts[i];
            }
        }
        return fonts[fonts.size() - 1];
    }

    //! Breaks `text` into lines that each fit `maxWidth` in `font`.
    //!
    //! Breaks on spaces. A single word longer than the line is split mid-word,
    //! because dropping it entirely would lose the one thing the line said.
    function wrap(dc, text, font, maxWidth) {
        var lines = [];
        if (text == null || text.length() == 0 || maxWidth <= 0) {
            return lines;
        }
        var words = split(text, ' ');
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            var word = words[i];
            if (word.length() == 0) {
                continue;
            }
            var candidate = (line.length() == 0) ? word : line + " " + word;
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) {
                line = candidate;
                continue;
            }
            if (line.length() > 0) {
                lines.add(line);
                line = "";
            }
            // The word alone may still be too wide.
            if (dc.getTextWidthInPixels(word, font) <= maxWidth) {
                line = word;
            } else {
                var chunks = hardSplit(dc, word, font, maxWidth);
                for (var c = 0; c < chunks.size() - 1; c++) {
                    lines.add(chunks[c]);
                }
                line = chunks[chunks.size() - 1];
            }
        }
        if (line.length() > 0) {
            lines.add(line);
        }
        return lines;
    }

    //! Splits an over-long word into pieces that each fit.
    function hardSplit(dc, word, font, maxWidth) {
        var out = [];
        var current = "";
        for (var i = 0; i < word.length(); i++) {
            var next = current + word.substring(i, i + 1);
            if (dc.getTextWidthInPixels(next, font) > maxWidth && current.length() > 0) {
                out.add(current);
                current = word.substring(i, i + 1);
            } else {
                current = next;
            }
        }
        out.add(current);
        return out;
    }

    //! `String.split` is not available on every API level this targets.
    function split(text, sep) {
        var out = [];
        var current = "";
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == sep) {
                out.add(current);
                current = "";
            } else {
                current += chars[i].toString();
            }
        }
        out.add(current);
        return out;
    }

    //! Draws `text` centred at `y`, wrapped, using the largest font that fits in
    //! `maxLines`. Returns the y below the last line, so callers can stack.
    function drawWrapped(dc, y, text, fonts, maxLines) {
        if (text == null || text.length() == 0) {
            return y;
        }
        var font = bestWrappedFont(dc, text, fonts, y, maxLines);
        var lines = wrap(dc, text, font, chordWidth(dc, y));
        var lineH = dc.getFontHeight(font);
        var cx = dc.getWidth() / 2;
        var drawn = 0;
        for (var i = 0; i < lines.size() && drawn < maxLines; i++) {
            // Re-measure per line: the chord narrows as we move down the screen.
            dc.drawText(cx, y + i * lineH, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            drawn++;
        }
        return y + drawn * lineH;
    }

    //! Draws one line centred at `y`, shrinking the font until it fits and
    //! truncating only if even the smallest will not.
    function drawFitted(dc, y, text, fonts) {
        if (text == null || text.length() == 0) {
            return y;
        }
        var maxWidth = chordWidth(dc, y);
        var font = bestFont(dc, text, fonts, maxWidth);
        var shown = text;
        if (dc.getTextWidthInPixels(shown, font) > maxWidth) {
            shown = clip(dc, shown, font, maxWidth);
        }
        dc.drawText(dc.getWidth() / 2, y, font, shown, Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(font);
    }

    //! Cuts `text` until it fits, marking the cut so a clipped line reads as one.
    function clip(dc, text, font, maxWidth) {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        var out = text;
        while (out.length() > 1) {
            out = out.substring(0, out.length() - 1);
            if (dc.getTextWidthInPixels(out + "...", font) <= maxWidth) {
                return out + "...";
            }
        }
        return out;
    }
}
