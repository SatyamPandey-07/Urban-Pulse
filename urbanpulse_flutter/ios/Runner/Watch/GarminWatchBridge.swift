import Foundation
import Flutter
import ConnectIQ

/// The phone end of the Garmin link on iOS, over the Connect IQ Companion App
/// SDK (`ConnectIQ.xcframework`, fetched by `ios/scripts/fetch_connectiq_sdk.sh`).
///
/// Three things about iOS shape this file, and none of them apply on Android.
///
/// **1. The device list only arrives via Garmin Connect.** There is no
/// `getKnownDevices()`. `showDeviceSelection()` launches Garmin Connect Mobile,
/// the traveller chooses what to share, and GCM returns to us by opening a URL
/// with our own scheme; `handleOpenURL` then parses it. Because there is no way
/// to ask again, the chosen devices are persisted here and reloaded at launch.
///
/// **2. `.connected` does not mean ready to send.** SDK 1.8 added
/// `deviceCharacteristicsDiscovered`, and the header is explicit that a device
/// reporting `.connected` may not yet have its services discovered. Reporting
/// "connected" at that point would produce a status row that says one thing while
/// every send fails, so [readyToSend] gates on the discovery callback and the
/// status stays `deviceNotConnected` until it fires.
///
/// **3. SOS from the watch is not offered on iOS.** No iOS API sends an SMS
/// without the traveller tapping send, so a wrist SOS could not complete on its
/// own. Rather than ship a hold-to-send button whose outcome is always "now go
/// find your phone", the Dart side disables it here and says so — see
/// `supportsSosFromWatch`.
final class GarminWatchBridge: NSObject {

    static let methodChannelName = "com.urbanpulse.app/garmin"
    static let eventChannelName = "com.urbanpulse.app/garmin_events"

    /// Must match `garmin/urbanpulse-watch/manifest.xml`.
    static let watchAppId = "f2ad5fab4ae240d984032ec48e3179d8"

    /// Our own URL scheme, which GCM uses to hand the device list back. Must match
    /// `CFBundleURLSchemes` in Info.plist.
    static let urlScheme = "urbanpulse-ciq"

    /// Lets the SDK's CBCentralManager be restored, so iOS can relaunch us in the
    /// background when a paired watch shows BLE activity.
    private static let restorationId = "com.urbanpulse.app.connectiq"

    private static let devicesKey = "connectiq_devices_v1"

    // The status strings the Dart side parses, kept as literals on both sides.
    private enum Status {
        static let connected = "connected"
        static let watchAppNotInstalled = "watchAppNotInstalled"
        static let deviceNotConnected = "deviceNotConnected"
        static let noDevicePaired = "noDevicePaired"
        static let garminAppMissing = "garminAppMissing"
    }

    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var events: FlutterEventSink?

    private var device: IQDevice?
    private var app: IQApp?

    /// Set once `deviceCharacteristicsDiscovered` fires for [device].
    private var readyToSend = false

    /// Set once `getAppStatus` confirms the watch app is installed.
    private var appInstalled = false

    /// Set when the SDK reports Garmin Connect Mobile is missing.
    private var gcmMissing = false

    private var initialized = false

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: GarminWatchBridge.methodChannelName,
                                            binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: GarminWatchBridge.eventChannelName,
                                           binaryMessenger: messenger)
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
        eventChannel.setStreamHandler(self)
    }

    // MARK: - method channel

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            connect(result)
        case "send":
            send(call, result)
        case "openWatchApp":
            openWatchApp(result)
        case "shutdown":
            shutdown()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func connect(_ result: @escaping FlutterResult) {
        guard let iq = ConnectIQ.sharedInstance() else {
            result(Status.deviceNotConnected)
            return
        }
        if !initialized {
            iq.initialize(withUrlScheme: GarminWatchBridge.urlScheme,
                          uiOverrideDelegate: self,
                          stateRestorationIdentifier: GarminWatchBridge.restorationId)
            initialized = true
            restoreDevices()
        }

        // Nothing remembered: the traveller has to pick a watch in Garmin Connect,
        // which means leaving the app. That is the SDK's only route, so we report
        // "no watch paired" and let the Connect button start the round trip.
        guard let device = device else {
            result(Status.noDevicePaired)
            emit(status: Status.noDevicePaired)
            requestDeviceSelection()
            return
        }

        subscribe(iq, device)
        let reported = currentStatus(iq)
        result(reported)
        emit(status: reported)
    }

    /// Launches Garmin Connect so the traveller can choose which watch to share.
    private func requestDeviceSelection() {
        ConnectIQ.sharedInstance()?.showDeviceSelection()
    }

    private func subscribe(_ iq: ConnectIQ, _ device: IQDevice) {
        // Registering is also what makes `getDeviceStatus` return anything other
        // than `.invalidDevice`, per the header.
        iq.register(forDeviceEvents: device, delegate: self)
        let app = watchApp(for: device)
        self.app = app
        iq.register(forAppMessages: app, delegate: self)
        iq.getAppStatus(app) { [weak self] status in
            guard let self = self else { return }
            self.appInstalled = status?.isInstalled ?? false
            self.emit(status: self.currentStatus(iq))
        }
    }

    private func watchApp(for device: IQDevice) -> IQApp {
        if let existing = app, existing.device.uuid == device.uuid { return existing }
        let uuid = UUID(uuidString: formatUuid(GarminWatchBridge.watchAppId)) ?? UUID()
        // `store` is nil: this build is side-loaded, not installed from the store.
        return IQApp(uuid: uuid, store: nil, device: device)!
    }

    /// The manifest carries a bare 32-character hex id; `UUID` wants the hyphens.
    private func formatUuid(_ raw: String) -> String {
        guard raw.count == 32, !raw.contains("-") else { return raw }
        let s = Array(raw)
        return String(s[0..<8]) + "-" + String(s[8..<12]) + "-" + String(s[12..<16])
            + "-" + String(s[16..<20]) + "-" + String(s[20..<32])
    }

    /// The one place a status is decided, so every caller agrees.
    private func currentStatus(_ iq: ConnectIQ) -> String {
        if gcmMissing { return Status.garminAppMissing }
        guard let device = device else { return Status.noDevicePaired }
        switch iq.getDeviceStatus(device) {
        case .connected:
            // Connected but not yet discovered is not sendable, so it is not
            // "connected" as far as the rest of the app is concerned.
            if !readyToSend { return Status.deviceNotConnected }
            return appInstalled ? Status.connected : Status.watchAppNotInstalled
        case .notFound:
            // iOS no longer knows this device; the traveller removed it.
            return Status.noDevicePaired
        case .notConnected, .bluetoothNotReady, .invalidDevice:
            return Status.deviceNotConnected
        @unknown default:
            return Status.deviceNotConnected
        }
    }

    private func send(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let iq = ConnectIQ.sharedInstance(), let app = app else {
            result(FlutterError(code: Status.noDevicePaired,
                                message: "No Garmin device to send to", details: nil))
            return
        }
        guard readyToSend else {
            // Sending before discovery completes fails inside the SDK with a less
            // useful error, so refuse here with the real reason.
            result(FlutterError(code: Status.deviceNotConnected,
                                message: "The watch is connected but not ready yet",
                                details: nil))
            return
        }
        guard let payload = call.arguments as? [String: Any] else {
            result(FlutterError(code: "badPayload", message: "Expected a map payload", details: nil))
            return
        }

        iq.sendMessage(stripNulls(payload), to: app, progress: nil) { sendResult in
            // Only the completion block knows; an accepted call is not a delivery.
            if sendResult == .success {
                result(nil)
            } else {
                let name = NSStringFromSendMessageResult(sendResult) ?? "failure"
                result(FlutterError(code: name,
                                    message: "Connect IQ reported \(name)", details: nil))
            }
        }
    }

    private func openWatchApp(_ result: @escaping FlutterResult) {
        guard let iq = ConnectIQ.sharedInstance(), let app = app else {
            result(gcmMissing ? Status.garminAppMissing : Status.deviceNotConnected)
            return
        }
        iq.openAppRequest(app) { [weak self] sendResult in
            guard let self = self else { return }
            let reported: String
            switch sendResult {
            case .success, .failure_PromptNotDisplayed, .failure_AppAlreadyRunning:
                // All three prove the app is on the watch.
                self.appInstalled = true
                reported = self.readyToSend ? Status.connected : Status.deviceNotConnected
            case .failure_AppNotFound:
                self.appInstalled = false
                reported = Status.watchAppNotInstalled
            default:
                reported = Status.deviceNotConnected
            }
            result(reported)
            self.emit(status: reported)
        }
    }

    private func shutdown() {
        guard let iq = ConnectIQ.sharedInstance() else { return }
        iq.unregister(forAllDeviceEvents: self)
        iq.unregister(forAllAppMessages: self)
        readyToSend = false
        appInstalled = false
    }

    func dispose() {
        shutdown()
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
        events = nil
    }

    // MARK: - the Garmin Connect round trip

    /// Handles a URL opened by Garmin Connect Mobile. Returns whether it was ours.
    ///
    /// Called from `AppDelegate`; this is the only way a device list ever reaches
    /// the app on iOS.
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == GarminWatchBridge.urlScheme else { return false }
        guard let iq = ConnectIQ.sharedInstance() else { return true }
        let parsed = iq.parseDeviceSelectionResponse(from: url)
        guard let devices = parsed as? [IQDevice], let first = devices.first else {
            // The traveller opened GCM and shared nothing.
            emit(status: Status.noDevicePaired)
            return true
        }
        device = first
        readyToSend = false
        appInstalled = false
        persist(devices)
        subscribe(iq, first)
        emit(status: currentStatus(iq))
        return true
    }

    private func persist(_ devices: [IQDevice]) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: devices,
                                                        requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: GarminWatchBridge.devicesKey)
        } catch {
            // Not fatal: the traveller is asked to pick a watch again next launch.
            NSLog("ConnectIQ: could not persist devices: \(error)")
        }
    }

    private func restoreDevices() {
        guard let data = UserDefaults.standard.data(forKey: GarminWatchBridge.devicesKey) else {
            return
        }
        let classes = [NSArray.self, IQDevice.self]
        let devices = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data)
        device = (devices as? [IQDevice])?.first
    }

    // MARK: - events

    private func emit(status: String) {
        onMain { self.events?(["status": status]) }
    }

    private func emit(message: [String: Any]) {
        guard !message.isEmpty else { return }
        onMain { self.events?(message) }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    /// Drops nulls, which are legal for the SDK but meaningless in our protocol.
    private func stripNulls(_ map: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in map {
            if value is NSNull { continue }
            if let nested = value as? [String: Any] {
                out[key] = stripNulls(nested)
            } else {
                out[key] = value
            }
        }
        return out
    }
}

// MARK: - IQDeviceEventDelegate

extension GarminWatchBridge: IQDeviceEventDelegate {

    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        guard device.uuid == self.device?.uuid else { return }
        if status != .connected {
            // A dropped link invalidates discovery; the next connect re-discovers.
            readyToSend = false
        }
        guard let iq = ConnectIQ.sharedInstance() else { return }
        emit(status: currentStatus(iq))
    }

    /// The device is genuinely ready now. Until this fires, sends fail.
    func deviceCharacteristicsDiscovered(_ device: IQDevice) {
        guard device.uuid == self.device?.uuid else { return }
        readyToSend = true
        guard let iq = ConnectIQ.sharedInstance() else { return }
        // Re-check the app now that we can actually talk to the watch.
        if let app = app {
            iq.getAppStatus(app) { [weak self] status in
                guard let self = self else { return }
                self.appInstalled = status?.isInstalled ?? false
                self.emit(status: self.currentStatus(iq))
            }
        } else {
            emit(status: currentStatus(iq))
        }
    }
}

// MARK: - IQAppMessageDelegate

extension GarminWatchBridge: IQAppMessageDelegate {

    func receivedMessage(_ message: Any, from app: IQApp) {
        // A message arriving proves the watch app is installed and running.
        if !appInstalled {
            appInstalled = true
            if let iq = ConnectIQ.sharedInstance() { emit(status: currentStatus(iq)) }
        }
        // Only a dictionary is a protocol message; anything else is dropped rather
        // than guessed at.
        guard let dict = message as? [String: Any] else { return }
        emit(message: stripNulls(dict))
    }
}

// MARK: - IQUIOverrideDelegate

extension GarminWatchBridge: IQUIOverrideDelegate {

    /// Garmin Connect Mobile is not installed. The settings row reports this; we
    /// deliberately do not open the App Store unprompted.
    func needsToInstallConnectMobile() {
        gcmMissing = true
        emit(status: Status.garminAppMissing)
    }
}

// MARK: - FlutterStreamHandler

extension GarminWatchBridge: FlutterStreamHandler {

    func onListen(withArguments arguments: Any?,
                  eventSink: @escaping FlutterEventSink) -> FlutterError? {
        events = eventSink
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        events = nil
        return nil
    }
}
