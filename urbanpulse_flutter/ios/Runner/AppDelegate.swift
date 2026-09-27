import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// The Connect IQ bridge. Held here because the Garmin Connect round trip comes
  /// back as an `openURL`, which only the app delegate sees.
  private var garmin: GarminWatchBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    garmin = GarminWatchBridge(messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// Garmin Connect Mobile returns the chosen devices by opening our URL scheme.
  ///
  /// Kept as a fallback for a non-scene configuration only. This app declares a
  /// `UISceneConfiguration`, so iOS routes URLs to `SceneDelegate` instead and
  /// this is never called — see the comment there.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if garmin?.handleOpenURL(url) == true {
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
