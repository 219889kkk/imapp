import UIKit
import Flutter
import FirebaseCore
import PushKit
import AVFAudio
import CallKit
import UserNotifications
import WebRTC
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, CallkitIncomingAppDelegate, HangXunVoipPushHandling {

    var replayKitChannel: FlutterMethodChannel! = nil
    var voipChannel: FlutterMethodChannel! = nil
    var apnsChannel: FlutterMethodChannel! = nil
    var observeTimer: Timer?
    var hasEmittedFirstSample = false
    private var voipRegistry: PKPushRegistry?
    private var voipPushDelegate: HangXunVoipPushDelegate?
    /// Fulfill non-invite VoIP without going through the plugin (no fake incoming UI).
    private var voipFulfillProvider: CXProvider?
    private let callKitEndController = CXCallController()
    private var lastCallKitAcceptAt: TimeInterval = 0
    /// roomID → endedAt (ignore late PushKit invites that re-show CallKit).
    private var endedVoipRooms: [String: Date] = [:]
    private let endedVoipRoomTTL: TimeInterval = 120

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            NSLog("HangXun: no FlutterViewController at launch — PushKit still registered")
            GeneratedPluginRegistrant.register(with: self)
            self.registerVoipPush()
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        FirebaseApp.configure()

        replayKitChannel = FlutterMethodChannel(name: "io.livekit.example.flutter/replaykit-channel", binaryMessenger: controller.binaryMessenger)
        voipChannel = FlutterMethodChannel(name: "top.hangxun.app/voip", binaryMessenger: controller.binaryMessenger)
        apnsChannel = FlutterMethodChannel(name: "top.hangxun.app/apns", binaryMessenger: controller.binaryMessenger)

        apnsChannel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterMethodNotImplemented)
                return
            }
            switch call.method {
            case "registerForRemoteNotifications":
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    NSLog("HangXun APNs: registerForRemoteNotifications")
                }
                result(true)
            case "getCachedApnsToken":
                result(UserDefaults.standard.string(forKey: "DevicePushTokenAPNs") ?? "")
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        voipChannel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterMethodNotImplemented)
                return
            }
            switch call.method {
            case "enableWebRtcAudio":
                let args = call.arguments as? [String: Any]
                let speaker = args?["speakerOn"] as? Bool ?? false
                self.enableWebRtcAudio(preferSpeaker: speaker, result: result)
            case "disableWebRtcAudio":
                self.disableWebRtcAudio(result: result)
            case "isWebRtcAudioEnabled":
                // Both flags required — isAudioEnabled alone can be true after a
                // dead setSpeakerRoute while the AVAudioSession is inactive.
                let rtc = RTCAudioSession.sharedInstance()
                result(rtc.isAudioEnabled && rtc.isActive)
            case "bridgeCallKitWebRtcAudio":
                self.bridgeCallKitWebRtcAudio(result: result)
            case "setSpeakerRoute":
                let args = call.arguments as? [String: Any]
                let speaker = args?["speakerOn"] as? Bool ?? false
                self.setSpeakerRoute(preferSpeaker: speaker, result: result)
            case "markRoomEnded":
                let args = call.arguments as? [String: Any]
                let roomID = (args?["roomID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !roomID.isEmpty {
                    self.markVoipRoomEnded(roomID)
                    NSLog("HangXun VoIP: markRoomEnded %@", roomID)
                }
                result(true)
            case "endAllCallKit":
                let args = call.arguments as? [String: Any]
                let roomID = (args?["roomID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.killAllCallKit(roomID: roomID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.killAllCallKit(roomID: roomID)
                }
                result(true)
            case "clearIconBadge":
                self.clearIconBadge()
                result(true)
            case "setLoginSessionHint":
                let args = call.arguments as? [String: Any]
                let active = args?["active"] as? Bool ?? false
                UserDefaults.standard.set(active, forKey: "hangxun.hasLoginSession")
                if !active {
                    self.clearIconBadge()
                }
                result(true)
            case "getCachedVoipToken":
                let token = UserDefaults.standard.string(forKey: "DevicePushTokenVoIP") ?? ""
                result(token)
            case "getApsEnvironment":
                // Prefer embedded provisioning entitlement over dart.vm.product guess.
                var env = "production"
                if let path = Bundle.main.path(forResource: "embedded.mobileprovision", ofType: nil),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let raw = String(data: data, encoding: .ascii) {
                    if raw.contains("<key>aps-environment</key>") {
                        if let range = raw.range(of: "<key>aps-environment</key>") {
                            let tail = String(raw[range.upperBound...])
                            if tail.contains("development") {
                                env = "sandbox"
                            }
                        }
                    }
                } else if let entitlements = Bundle.main.infoDictionary?["Entitlements"] as? [String: Any],
                          let aps = entitlements["aps-environment"] as? String,
                          aps == "development" {
                    env = "sandbox"
                }
                // Ad-hoc / TF / App Store profiles are production even when
                // Runner.entitlements in source says development.
                result(env)
            case "isApplicationActive":
                result(UIApplication.shared.applicationState == .active)
            case "getPendingIncomingRoom":
                result(self.pendingIncomingRoomID())
            case "clearPendingIncomingRoom":
                self.clearPendingIncomingRoom()
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        replayKitChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            self.handleReplayKitFromFlutter(result: result, call: call)
        })

        // WebRTC manual audio: CallKit activates/deactivates via didActivateAudioSession.
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false

        // CallKit owns activation on lock-screen answer — AppDelegate bridges to WebRTC.
        GeneratedPluginRegistrant.register(with: self)

        // After CallKit plugin is up: every VoIP wake can report incoming before completion.
        self.registerVoipPush()

        // Overlay IPA keeps UserDefaults. A leftover "logged in" hint would skip
        // badge wipes while Flutter is still on the login page. Dart re-arms
        // the hint only after IM login succeeds, then restores real unread.
        UserDefaults.standard.set(false, forKey: "hangxun.hasLoginSession")
        self.clearIconBadge()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Wipe SpringBoard badge without touching OpenIM (safe before login).
    /// Never remove delivered/pending notifications — that cancels incoming-call
    /// banners / CallKit companions while a ring is in progress.
    private func clearIconBadge() {
        applyZeroBadge()
        // Permission / Getui / APNs can restore a stale number — clear again shortly.
        for delay in [0.5, 2.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !self.hasActiveLoginHint() {
                    self.applyZeroBadge()
                }
            }
        }
    }

    private func applyZeroBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { error in
                if let error = error {
                    NSLog("HangXun clearIconBadge setBadgeCount failed: %@", error.localizedDescription)
                }
            }
        }
    }

    private func wipeBadgeIfLoggedOut() {
        if !hasActiveLoginHint() {
            clearIconBadge()
        }
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        // Permission dialog / push wake can restore a stale badge before login.
        // Dart will re-apply the real unread count after IM login.
        wipeBadgeIfLoggedOut()
    }

    override func applicationWillEnterForeground(_ application: UIApplication) {
        super.applicationWillEnterForeground(application)
        wipeBadgeIfLoggedOut()
    }

    /// Best-effort: UserDefaults flag written by Flutter after IM login succeeds.
    private func hasActiveLoginHint() -> Bool {
        UserDefaults.standard.bool(forKey: "hangxun.hasLoginSession")
    }

    /// Required so APNs can wake the app when backgrounded.
    /// APNs `badge` is applied by SpringBoard even before login — wipe it then.
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        wipeBadgeIfLoggedOut()
        completionHandler(.newData)
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: "DevicePushTokenAPNs")
        NSLog("HangXun APNs token: %@", hex)
        apnsChannel?.invokeMethod("onApnsToken", arguments: hex)
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("HangXun APNs register failed: %@", error.localizedDescription)
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if !hasActiveLoginHint() {
            applyZeroBadge()
            completionHandler([])
            return
        }
        super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        wipeBadgeIfLoggedOut()
        super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    // MARK: - CallkitIncomingAppDelegate (required by flutter_callkit_incoming)

    /// Dart handles accept via FlutterCallkitIncoming.onEvent — fulfill so CallKit activates audio.
    func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
        NSLog("HangXun CallKit: onAccept room=%@", call.data.uuid)
        lastCallKitAcceptAt = Date().timeIntervalSince1970
        // Configure category BEFORE fulfill so CallKit can activate session on lock screen.
        // Do NOT setActive here — CallKit owns activation (didActivateAudioSession).
        let session = AVAudioSession.sharedInstance()
        do {
            try applyVoipAudioSession(session, preferSpeaker: false, activate: false)
            emitAudioDebug("CallKit onAccept category configured room=\(call.data.uuid)")
        } catch {
            emitAudioDebug("CallKit onAccept category failed \(error.localizedDescription)")
        }
        action.fulfill()
    }

    /// VoIP audio: voiceChat + HFP bluetooth only (no A2DP — A2DP kills hardware AEC).
    /// Speaker uses ~20ms IO buffer so echo cancellation can converge; earpiece can be tighter.
    private func applyVoipAudioSession(
        _ session: AVAudioSession,
        preferSpeaker: Bool,
        activate: Bool
    ) throws {
        var options: AVAudioSession.CategoryOptions = [.allowBluetooth]
        if preferSpeaker {
            options.insert(.defaultToSpeaker)
        }
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try session.setPreferredSampleRate(48000)
        // Stable 20ms for both routes — tighter buffers delay AEC convergence
        // and made the first seconds after answer sound muddy.
        try session.setPreferredIOBufferDuration(0.02)
        if activate {
            try session.setActive(true, options: [])
        }
        try session.overrideOutputAudioPort(preferSpeaker ? .speaker : .none)
    }

    /// Switch earpiece ↔ speaker while keeping voiceChat AEC. Sync RTCAudioSession.
    /// After CallKit didDeactivate the session is dead — must setActive again or
    /// isAudioEnabled=true with an inactive session leaves every call silent.
    private func setSpeakerRoute(preferSpeaker: Bool, result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        do {
            // When WebRTC session is inactive (post-CallKit handoff), setActive.
            // While CallKit still owns activation, rtc.isActive is already true.
            let activate = !rtc.isActive
            try applyVoipAudioSession(session, preferSpeaker: preferSpeaker, activate: activate)
            rtc.audioSessionDidActivate(session)
            rtc.isAudioEnabled = true
            emitAudioDebug("setSpeakerRoute speaker=\(preferSpeaker) activate=\(activate) mode=voiceChat aec=on")
            result(true)
        } catch {
            emitAudioDebug("setSpeakerRoute failed \(error.localizedDescription)")
            result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
        }
    }

    func onDecline(_ call: Call, _ action: CXEndCallAction) {
        let sinceAccept = Date().timeIntervalSince1970 - lastCallKitAcceptAt
        NSLog("HangXun CallKit: onDecline room=%@ sinceAccept=%.3f", call.data.uuid, sinceAccept)
        action.fulfill()
    }

    func onEnd(_ call: Call, _ action: CXEndCallAction) {
        NSLog("HangXun CallKit: onEnd room=%@", call.data.uuid)
        action.fulfill()
        // User (or system) actually ended the CXCall — Dart must hang up.
        // Programmatic endCall is ignored via uiDismiss on the Dart side.
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onCallKitUserEnd", arguments: [
                "roomID": call.data.uuid,
            ])
        }
    }

    func onTimeOut(_ call: Call) {
        NSLog("HangXun CallKit: onTimeOut room=%@", call.data.uuid)
    }

    func providerDidReset() {
        NSLog("HangXun CallKit: providerDidReset")
    }

    // MARK: - CallKit audio session → WebRTC (lock-screen talk)

    private func emitAudioDebug(_ message: String) {
        NSLog("HangXun WebRTC: %@", message)
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onAudioDebug", arguments: [
                "tag": "native",
                "message": message,
            ])
        }
    }

    func didActivateAudioSession(_ audioSession: AVAudioSession) {
        // Keep voiceChat (hardware AEC). Do not add A2DP — it breaks echo cancellation.
        do {
            try applyVoipAudioSession(audioSession, preferSpeaker: false, activate: false)
        } catch {
            emitAudioDebug("CallKit didActivate category failed \(error.localizedDescription)")
        }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        rtc.audioSessionDidActivate(audioSession)
        rtc.isAudioEnabled = true
        rtc.unlockForConfiguration()
        emitAudioDebug("CallKit audio session activated isAudioEnabled=true")
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onCallKitAudioActivated", arguments: nil)
        }
    }

    func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        rtc.audioSessionDidDeactivate(audioSession)
        rtc.isAudioEnabled = false
        rtc.unlockForConfiguration()
        emitAudioDebug("CallKit audio session deactivated isAudioEnabled=false")
        // Tell Flutter immediately so it can take over with setActive before UI
        // setSpeakerRoute races and marks isAudioEnabled without a live session.
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onCallKitAudioDeactivated", arguments: nil)
        }
    }

    // MARK: - WebRTC audio (in-app calls — useManualAudio requires explicit enable)

    private func enableWebRtcAudio(preferSpeaker: Bool, result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        do {
            try applyVoipAudioSession(session, preferSpeaker: preferSpeaker, activate: true)
            rtc.audioSessionDidActivate(session)
            rtc.isAudioEnabled = true
            emitAudioDebug("in-app audio enabled speaker=\(preferSpeaker) isActive=\(rtc.isActive)")
            result(true)
        } catch {
            // CallKit tear-down often races setActive — retry quickly.
            emitAudioDebug("in-app enable failed \(error.localizedDescription) — retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let session = AVAudioSession.sharedInstance()
                let rtc = RTCAudioSession.sharedInstance()
                rtc.lockForConfiguration()
                defer { rtc.unlockForConfiguration() }
                do {
                    try self.applyVoipAudioSession(session, preferSpeaker: preferSpeaker, activate: true)
                    rtc.audioSessionDidActivate(session)
                    rtc.isAudioEnabled = true
                    self.emitAudioDebug("in-app audio enabled on retry speaker=\(preferSpeaker)")
                    result(true)
                } catch {
                    self.emitAudioDebug("in-app enable retry failed \(error.localizedDescription)")
                    result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func disableWebRtcAudio(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        rtc.isAudioEnabled = false
        rtc.audioSessionDidDeactivate(session)
        rtc.unlockForConfiguration()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            emitAudioDebug("in-app audio disabled + session deactivated")
        } catch {
            emitAudioDebug("session setActive(false) failed \(error.localizedDescription)")
        }
        result(true)
    }

    /// CallKit already activated AVAudioSession — bridge WebRTC without setActive.
    private func bridgeCallKitWebRtcAudio(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        do {
            try applyVoipAudioSession(session, preferSpeaker: false, activate: false)
        } catch {
            emitAudioDebug("CallKit bridge category failed \(error.localizedDescription)")
        }
        rtc.audioSessionDidActivate(session)
        rtc.isAudioEnabled = true
        emitAudioDebug("CallKit bridge (no setActive) isAudioEnabled=true")
        result(true)
    }

    // MARK: - PushKit (VoIP)

    private func registerVoipPush() {
        if voipRegistry != nil {
            return
        }
        loadEndedVoipRoomsIfNeeded()
        let pushDelegate = HangXunVoipPushDelegate()
        pushDelegate.handler = self
        self.voipPushDelegate = pushDelegate
        let registry = PKPushRegistry(queue: DispatchQueue.main)
        registry.delegate = pushDelegate
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry
        NSLog("HangXun VoIP: PKPushRegistry registered")
    }

    func hangxunDidUpdateVoipToken(_ token: Foundation.Data) {
        let deviceToken = token.map { String(format: "%02x", $0) }.joined()
        NSLog("HangXun VoIP token: %@", deviceToken)

        HangXunGetuiVoip.registerPushKitToken(token)

        UserDefaults.standard.set(deviceToken, forKey: "DevicePushTokenVoIP")
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)

        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onVoipToken", arguments: deviceToken)
        }
    }

    func hangxunDidInvalidateVoipToken() {
        NSLog("HangXun VoIP: token invalidated")
        UserDefaults.standard.set("", forKey: "DevicePushTokenVoIP")
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
    }

    /// Flatten Getui / APNs VoIP payload (may be JSON string under payload/transmission).
    private func flattenVoipPayload(_ dict: [AnyHashable: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]

        func absorb(_ source: [String: Any]) {
            for (key, value) in source {
                merged[String(describing: key)] = value
            }
        }

        func absorbJSONString(_ raw: String) {
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            absorb(json)
        }

        for (key, value) in dict {
            let k = String(describing: key)
            if let s = value as? String, (k == "payload" || k == "transmission" || k == "content") {
                absorbJSONString(s)
            } else if let nested = value as? [String: Any] {
                absorb(nested)
            } else {
                merged[k] = value
            }
        }

        return merged
    }


    private let endedVoipRoomsDefaultsKey = "hangxun.endedVoipRooms"

    private func markVoipRoomEnded(_ roomID: String) {
        loadEndedVoipRoomsIfNeeded()
        let id = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        pruneEndedVoipRooms()
        endedVoipRooms[id] = Date()
        persistEndedVoipRooms()
        let pending = (UserDefaults.standard.string(forKey: pendingIncomingRoomKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if pending == id {
            clearPendingIncomingRoom()
        }
    }

    private func isVoipRoomEnded(_ roomID: String) -> Bool {
        loadEndedVoipRoomsIfNeeded()
        pruneEndedVoipRooms()
        let id = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        if endedVoipRooms[id] != nil { return true }
        let compact = compactCallUUID(id)
        return endedVoipRooms.contains { compactCallUUID($0.key) == compact }
    }

    private func pruneEndedVoipRooms() {
        let cutoff = Date().addingTimeInterval(-endedVoipRoomTTL)
        let before = endedVoipRooms.count
        endedVoipRooms = endedVoipRooms.filter { $0.value >= cutoff }
        if endedVoipRooms.count != before {
            persistEndedVoipRooms()
        }
    }

    private var endedVoipRoomsLoaded = false

    private func loadEndedVoipRoomsIfNeeded() {
        guard !endedVoipRoomsLoaded else { return }
        endedVoipRoomsLoaded = true
        guard let raw = UserDefaults.standard.dictionary(
            forKey: endedVoipRoomsDefaultsKey
        ) as? [String: Double] else { return }
        let now = Date()
        for (id, ts) in raw {
            let date = Date(timeIntervalSince1970: ts)
            if now.timeIntervalSince(date) <= endedVoipRoomTTL {
                endedVoipRooms[id] = date
            }
        }
    }

    private func persistEndedVoipRooms() {
        var map: [String: Double] = [:]
        for (id, date) in endedVoipRooms {
            map[id] = date.timeIntervalSince1970
        }
        UserDefaults.standard.set(map, forKey: endedVoipRoomsDefaultsKey)
    }

    private func compactCallUUID(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "-", with: "")
    }

    private func uuidMatchesRoom(_ uuid: UUID, roomID: String) -> Bool {
        compactCallUUID(uuid.uuidString) == compactCallUUID(roomID)
    }

    private func requestEndCall(_ uuid: UUID) {
        let tx = CXTransaction(action: CXEndCallAction(call: uuid))
        callKitEndController.request(tx) { error in
            if let error = error {
                NSLog("HangXun CallKit: CXEndCall %@ %@", uuid.uuidString, error.localizedDescription)
            }
        }
    }

    private func pluginEndCall(id: String) {
        let endData = flutter_callkit_incoming.Data(args: [
            "id": id,
            "nameCaller": "",
            "handle": "",
            "type": 0,
        ])
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(endData)
    }

    private func pluginEndAllCalls() {
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endAllCalls()
    }

    private func endAllActiveCallKitCalls() {
        killAllCallKit(roomID: pendingIncomingRoomID())
    }

    private func shouldForceEndAllCallKit(for roomID: String) -> Bool {
        let pending = pendingIncomingRoomID()
        if pending == roomID { return true }
        let calls = CXCallObserver().calls.filter { !$0.hasEnded }
        if calls.isEmpty { return false }
        for call in calls {
            if uuidMatchesRoom(call.uuid, roomID: roomID) { continue }
            if isVoipRoomEnded(call.uuid.uuidString) { continue }
            if !pending.isEmpty && pending != roomID { return false }
        }
        return true
    }

    private func endCallKitCalls(roomID: String, forceEndAll: Bool) {
        pluginEndCall(id: roomID)

        let calls = CXCallObserver().calls.filter { !$0.hasEnded }
        for call in calls {
            if uuidMatchesRoom(call.uuid, roomID: roomID) || forceEndAll {
                requestEndCall(call.uuid)
                pluginEndCall(id: call.uuid.uuidString)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            self.pluginEndCall(id: roomID)
            if forceEndAll {
                self.endAllActiveCallKitCalls()
            }
        }
    }

    private func notifyDartVoipRemoteEnd(roomID: String, action: String) {
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onVoipRemoteEnd", arguments: [
                "roomID": roomID,
                "action": action,
            ])
        }
    }

    private let pendingIncomingRoomKey = "hangxun.pendingIncomingRoomID"
    private let pendingIncomingAtKey = "hangxun.pendingIncomingAt"
    private let pendingIncomingTTL: TimeInterval = 60

    private func persistPendingIncomingRoom(_ roomID: String) {
        let id = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        UserDefaults.standard.set(id, forKey: pendingIncomingRoomKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingIncomingAtKey)
    }

    private func pendingIncomingRoomID() -> String {
        let id = (UserDefaults.standard.string(forKey: pendingIncomingRoomKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "" }
        if isVoipRoomEnded(id) {
            clearPendingIncomingRoom()
            return ""
        }
        let at = UserDefaults.standard.double(forKey: pendingIncomingAtKey)
        if at > 0, Date().timeIntervalSince1970 - at > pendingIncomingTTL {
            clearPendingIncomingRoom()
            return ""
        }
        return id
    }

    private func clearPendingIncomingRoom() {
        UserDefaults.standard.removeObject(forKey: pendingIncomingRoomKey)
        UserDefaults.standard.removeObject(forKey: pendingIncomingAtKey)
    }

    private let trackedCallRoomKey = "hangxun.trackedCallRoomID"

    private func setTrackedCallRoom(_ roomID: String) {
        let id = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        UserDefaults.standard.set(id, forKey: trackedCallRoomKey)
    }

    private func trackedCallRoomID() -> String {
        (UserDefaults.standard.string(forKey: trackedCallRoomKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearTrackedCallRoom(_ roomID: String) {
        let id = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let tracked = trackedCallRoomID()
        if id.isEmpty || tracked.isEmpty || tracked == id {
            UserDefaults.standard.removeObject(forKey: trackedCallRoomKey)
        }
    }

    private func notifyDartVoipCallKitPresented(roomID: String) {
        persistPendingIncomingRoom(roomID)
        let fire: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.voipChannel?.invokeMethod("onVoipCallKitPresented", arguments: [
                "roomID": roomID,
            ])
        }
        // Dart isolate is often not listening yet on killed-app VoIP wake.
        // Persist + retries so prejoin starts while CallKit is still ringing.
        DispatchQueue.main.async { fire() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.pendingIncomingRoomID() == roomID {
                fire()
            }
        }
    }

    /// iOS 13+: report-required VoIP must CallKit-report before `completion`.
    /// iOS 26.4+: `mustReport` comes from PKVoIPPushMetadata.
    func hangxunDidReceiveVoipPayload(
        _ payload: PKPushPayload,
        mustReport: Bool,
        completion: @escaping () -> Void
    ) {
        let dict = flattenVoipPayload(payload.dictionaryPayload)
        NSLog("HangXun VoIP payload (flat) mustReport=%@ %@", mustReport ? "1" : "0", dict)

        HangXunGetuiVoip.handlePushKitPayload(dict)

        let action = voipEndAction(from: dict)
        let roomID = (dict["roomID"] as? String)
            ?? (dict["callUUID"] as? String)
            ?? (dict["id"] as? String)
            ?? UUID().uuidString

        if action == "cancel" || action == "end" || action == "hungup" || action == "reject" {
            NSLog("HangXun VoIP remote end action=%@ room=%@", action, roomID)
            markVoipRoomEnded(roomID)
            notifyDartVoipRemoteEnd(roomID: roomID, action: action)
            fulfillVoipEndAction(roomID: roomID, dict: dict, mustReport: mustReport, completion: completion)
            return
        }

        if action == "accept" || action == "answered" {
            NSLog("HangXun VoIP peer accept room=%@ — mustReport without caller banner", roomID)
            notifyDartVoipRemoteEnd(roomID: roomID, action: "accept")
            // iOS 13+/26: skip reportNewIncomingCall → VoIP 被停掉，三种被叫全挂。
            fulfillVoipWithoutIncomingUi(mustReport: mustReport, completion: completion)
            return
        }

        if isVoipRoomEnded(roomID) {
            NSLog("HangXun VoIP: room already ended %@", roomID)
            fulfillVoipEndAction(roomID: roomID, dict: dict, mustReport: mustReport, completion: completion)
            return
        }

        if !hasActiveLoginHint() {
            NSLog("HangXun VoIP: login hint false — still show CallKit room=%@", roomID)
        }

        if !mustReport {
            NSLog("HangXun VoIP: mustReport=0 invite room=%@ — notify Dart only", roomID)
            notifyDartVoipCallKitPresented(roomID: roomID)
            completion()
            return
        }

        // 状态 3：应用内全屏邀请。仍必须 CallKit-report，否则系统停掉 VoIP。
        // 用一次性假 UUID，不要真实 roomID（否则顶栏+全屏两套 UI）。
        let appState = UIApplication.shared.applicationState
        if appState == .active {
            NSLog("HangXun VoIP: in-app invite — mustReport dummy room=%@", roomID)
            notifyDartVoipCallKitPresented(roomID: roomID)
            fulfillVoipWithoutIncomingUi(mustReport: mustReport, completion: completion)
            return
        }

        reportIncomingCallKit(roomID: roomID, dict: dict, notifyDart: true, completion: completion)
    }

    private func incomingCallKitData(roomID: String, dict: [String: Any]) -> flutter_callkit_incoming.Data {
        let mediaType = (dict["mediaType"] as? String) ?? "audio"
        let isVideo = mediaType == "video"
        let nameCaller = (dict["nickname"] as? String)
            ?? (dict["inviterNickname"] as? String)
            ?? (dict["nameCaller"] as? String)
            ?? "来电"
        var handle = (dict["inviterUserID"] as? String)
            ?? (dict["handle"] as? String)
            ?? "hangxun"
        if handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handle = "hangxun"
        }
        var timeoutSec = 60
        if let t = dict["timeout"] as? Int {
            timeoutSec = t
        } else if let t = dict["timeout"] as? String, let v = Int(t) {
            timeoutSec = v
        } else if let t = dict["timeout"] as? Double {
            timeoutSec = Int(t)
        }
        if timeoutSec < 30 { timeoutSec = 60 }
        var info: [String: Any?] = [:]
        info["id"] = roomID
        info["nameCaller"] = nameCaller
        info["appName"] = "航讯"
        info["handle"] = handle
        info["type"] = isVideo ? 1 : 0
        info["duration"] = timeoutSec * 1000
        info["extra"] = dict
        let data = flutter_callkit_incoming.Data(args: info)
        data.configureAudioSession = false
        data.audioSessionActive = false
        return data
    }

    private func reportIncomingCallKit(
        roomID: String,
        dict: [String: Any],
        notifyDart: Bool,
        completion: @escaping () -> Void
    ) {
        let data = incomingCallKitData(roomID: roomID, dict: dict)
        let appState = UIApplication.shared.applicationState
        NSLog("HangXun VoIP: report CallKit room=%@ state=%ld", roomID, appState.rawValue)
        setTrackedCallRoom(roomID)
        if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
            plugin.showCallkitIncoming(data, fromPushKit: true) {
                completion()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: completion)
        }
        if notifyDart {
            notifyDartVoipCallKitPresented(roomID: roomID)
        }
    }

    private func callKitHasUUID(_ roomID: String) -> Bool {
        let target = roomID.lowercased()
        return CXCallObserver().calls.contains { $0.uuid.uuidString.lowercased() == target }
    }

    /// Cancel / hungup / reject: end this room's CallKit, then mustReport dummy if needed.
    /// Dummy must end in the same report callback — leaving it up was the leftover timer.
    private func fulfillVoipEndAction(
        roomID: String,
        dict: [String: Any],
        mustReport: Bool,
        completion: @escaping () -> Void
    ) {
        // End this room first (pending/tracked still set so Answer-swapped UUID is wiped).
        killCallKit(for: roomID)
        if pendingIncomingRoomID() == roomID {
            clearPendingIncomingRoom()
        }
        clearTrackedCallRoom(roomID)
        fulfillVoipWithoutIncomingUi(mustReport: mustReport) { [weak self] in
            self?.killCallKit(for: roomID)
            completion()
        }
    }

    /// Incoming + connected (timer) CallKit. Answer swaps UUID; end roomID alone is not enough.
    /// Do not wipe a *different* room's ringing call (stale cancel used to kill the next invite).
    private func killAllCallKit(roomID: String) {
        killCallKit(for: roomID)
    }

    private func killCallKit(for roomID: String) {
        pluginEndCall(id: roomID)
        let pending = pendingIncomingRoomID()
        let tracked = trackedCallRoomID()
        let wipeAll = roomID.isEmpty
            || pending == roomID
            || tracked == roomID
            || (pending.isEmpty && tracked.isEmpty)
        for call in CXCallObserver().calls where !call.hasEnded {
            if uuidMatchesRoom(call.uuid, roomID: roomID) || wipeAll {
                requestEndCall(call.uuid)
                pluginEndCall(id: call.uuid.uuidString)
                voipFulfillProvider?.reportCall(with: call.uuid, endedAt: Date(), reason: .remoteEnded)
            }
        }
        if wipeAll {
            pluginEndAllCalls()
        }
        if wipeAll || pending == roomID {
            clearTrackedCallRoom(roomID)
        }
    }

    /// Invite vs end: `action` may be missing; customType / body still say "ended".
    private func voipEndAction(from dict: [String: Any]) -> String {
        var action = ((dict["action"] as? String) ?? "").lowercased()
        if action.isEmpty {
            var customType = 0
            if let n = dict["customType"] as? Int {
                customType = n
            } else if let n = dict["customType"] as? NSNumber {
                customType = n.intValue
            } else if let s = dict["customType"] as? String, let n = Int(s) {
                customType = n
            }
            switch customType {
            case 201: action = "accept"
            case 202: action = "reject"
            case 203: action = "cancel"
            case 204: action = "hungup"
            default: break
            }
        }
        if action.isEmpty {
            let body = ((dict["body"] as? String) ?? "")
            if body.contains("已结束") || body.lowercased().contains("ended") {
                action = "cancel"
            }
        }
        return action
    }

    /// iOS 13+/26 require reportNewIncomingCall before VoIP completion.
    /// Throwaway UUID, ended in the same callback so it does not become a timer page.
    private func fulfillVoipWithoutIncomingUi(
        mustReport: Bool,
        completion: @escaping () -> Void
    ) {
        if !mustReport {
            NSLog("HangXun VoIP: skip incoming UI fulfill mustReport=0")
            completion()
            return
        }
        let uuid = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "hangxun")
        update.localizedCallerName = " "
        update.hasVideo = false
        if voipFulfillProvider == nil {
            let config = CXProviderConfiguration()
            config.supportedHandleTypes = [.generic]
            config.maximumCallGroups = 1
            config.maximumCallsPerCallGroup = 1
            voipFulfillProvider = CXProvider(configuration: config)
        }
        let provider = voipFulfillProvider!
        NSLog("HangXun VoIP: dummy CallKit fulfill uuid=%@", uuid.uuidString)
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
            provider.reportCall(with: uuid, endedAt: Date(), reason: .answeredElsewhere)
            self?.requestEndCall(uuid)
            DispatchQueue.main.async(execute: completion)
        }
    }

    func handleReplayKitFromFlutter(result: FlutterResult, call: FlutterMethodCall) {
        switch call.method {
        case "startReplayKit":
            self.hasEmittedFirstSample = false
            let group = UserDefaults(suiteName: "group.io.livekit.example.flutter")
            group!.set(false, forKey: "closeReplayKitFromNative")
            group!.set(false, forKey: "closeReplayKitFromFlutter")
            self.observeReplayKitStateChanged()
        case "closeReplayKit":
            let group = UserDefaults(suiteName: "group.io.livekit.example.flutter")
            group!.set(true, forKey: "closeReplayKitFromFlutter")
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func observeReplayKitStateChanged() {
        if self.observeTimer != nil {
            return
        }

        let group = UserDefaults(suiteName: "group.io.livekit.example.flutter")
        self.observeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { (_) in
            let closeReplayKitFromNative = group!.bool(forKey: "closeReplayKitFromNative")
            let hasSampleBroadcast = group!.bool(forKey: "hasSampleBroadcast")

            if closeReplayKitFromNative {
                self.hasEmittedFirstSample = false
                self.replayKitChannel.invokeMethod("closeReplayKitFromNative", arguments: true)
            } else if hasSampleBroadcast {
                if !self.hasEmittedFirstSample {
                    self.hasEmittedFirstSample = true
                    self.replayKitChannel.invokeMethod("hasSampleBroadcast", arguments: true)
                }
            }
        }
    }
}
