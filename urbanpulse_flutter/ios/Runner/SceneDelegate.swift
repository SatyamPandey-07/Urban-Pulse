import Flutter
import UIKit

/// The app's scene delegate.
///
/// It exists in this project only because the storyboard declares a
/// `UISceneConfiguration`, but that has one consequence worth knowing: on a
/// scene-based app iOS delivers incoming URLs **here**, and never to
/// `AppDelegate.application(_:open:options:)`.
///
/// That matters because the Connect IQ device-selection round trip comes back as
/// a URL. Left to `FlutterSceneDelegate`, that URL is forwarded to Flutter's
/// navigation channel and Dart throws `Could not find a generator for route
/// "/?ciqApp=Connect&..."` — the device list silently never arrives. So our
/// scheme is intercepted before `super` sees it.
class SceneDelegate: FlutterSceneDelegate {

    /// A URL opened while the app is already running.
    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let unhandled = consumeGarminURLs(URLContexts)
        // Anything that was not ours still needs the default handling (deep
        // links, url_launcher callbacks).
        if !unhandled.isEmpty {
            super.scene(scene, openURLContexts: unhandled)
        }
    }

    /// A URL that launched the app from cold.
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        // The bridge may not exist yet at cold launch; `handleOpenURL` is safe to
        // miss here because the SDK has not been initialised either, and the
        // traveller's next tap on Connect re-runs the round trip.
        _ = consumeGarminURLs(connectionOptions.urlContexts)
    }

    /// Hands any Connect IQ URLs to the bridge and returns the rest.
    private func consumeGarminURLs(_ contexts: Set<UIOpenURLContext>) -> Set<UIOpenURLContext> {
        guard let bridge = GarminWatchBridge.shared else { return contexts }
        return contexts.filter { !bridge.handleOpenURL($0.url) }
    }
}
