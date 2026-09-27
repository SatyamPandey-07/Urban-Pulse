import Toybox.Lang;
import Toybox.System;
import Toybox.Attention;

//! Vibration, and when not to.
//!
//! Three gates, all of them the watch's own settings rather than ours:
//!   * the device may have no vibration motor at all (`Attention has :vibrate`),
//!   * the traveller may have vibration switched off (`vibrateOn`),
//!   * the traveller may be in do-not-disturb, in which case an Urban Pulse
//!     alert is exactly the kind of thing they asked not to feel. The text still
//!     appears; only the buzz is suppressed.
module Buzz {

    //! A distinct pattern per kind, short enough to read through a jacket.
    //! `VibeProfile(dutyCycle 0-100, duration ms)`.
    function forKind(kind) {
        if (kind == null) {
            return [new Attention.VibeProfile(50, 250)];
        }
        if (kind.equals(Protocol.KIND_LEAVE)) {
            // Two firm taps: get up and go.
            return [new Attention.VibeProfile(75, 250),
                    new Attention.VibeProfile(0, 150),
                    new Attention.VibeProfile(75, 250)];
        }
        if (kind.equals(Protocol.KIND_ARRIVED)) {
            // One soft confirmation.
            return [new Attention.VibeProfile(50, 400)];
        }
        if (kind.equals(Protocol.KIND_LATE)) {
            // Three quick urgent taps.
            return [new Attention.VibeProfile(100, 150),
                    new Attention.VibeProfile(0, 100),
                    new Attention.VibeProfile(100, 150),
                    new Attention.VibeProfile(0, 100),
                    new Attention.VibeProfile(100, 150)];
        }
        if (kind.equals(Protocol.KIND_MEAL)) {
            // A gentle double, lower duty cycle: not urgent.
            return [new Attention.VibeProfile(40, 200),
                    new Attention.VibeProfile(0, 200),
                    new Attention.VibeProfile(40, 200)];
        }
        if (kind.equals(Protocol.KIND_RAIN)) {
            // A long fade, like weather arriving.
            return [new Attention.VibeProfile(30, 300),
                    new Attention.VibeProfile(60, 300)];
        }
        return [new Attention.VibeProfile(50, 250)];
    }

    //! True when this watch will actually vibrate right now.
    function allowed() {
        if (!(Attention has :vibrate)) {
            return false;
        }
        var settings = System.getDeviceSettings();
        if (settings == null) {
            return false;
        }
        if (settings has :vibrateOn && !settings.vibrateOn) {
            return false;
        }
        // Not every device reports do-not-disturb; where it does, honour it.
        if (settings has :doNotDisturb && settings.doNotDisturb) {
            return false;
        }
        return true;
    }

    //! Buzzes for `kind`. Returns whether it actually did, so a caller can tell
    //! a suppressed buzz from a delivered one.
    function forAlert(kind) {
        if (!allowed()) {
            return false;
        }
        Attention.vibrate(forKind(kind));
        return true;
    }

    //! The SOS confirmation: long and unmistakable. This one ignores
    //! do-not-disturb, because the traveller asked for it a moment ago by
    //! holding the button for three seconds.
    function forSos() {
        if (!(Attention has :vibrate)) {
            return false;
        }
        var settings = System.getDeviceSettings();
        if (settings != null && settings has :vibrateOn && !settings.vibrateOn) {
            return false;
        }
        Attention.vibrate([new Attention.VibeProfile(100, 600),
                           new Attention.VibeProfile(0, 200),
                           new Attention.VibeProfile(100, 600)]);
        return true;
    }

    //! A short tick while the SOS hold is building, so the traveller can feel
    //! that the press registered.
    function tick() {
        if (!allowed()) {
            return false;
        }
        Attention.vibrate([new Attention.VibeProfile(25, 60)]);
        return true;
    }
}
