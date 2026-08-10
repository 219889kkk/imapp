import UIKit
import Flutter
import FirebaseCore
import PushKit
import AVFAudio
import CallKit
import WebRTC
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {

    var replayKitChannel: FlutterMethodChannel! = nil
    var voipChannel: FlutterMethodChannel! = nil
    var observeTimer: Timer?
    var hasEmittedFirstSample = false
    private var voipRegistry: PKPushRegistry?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        FirebaseApp.configure()

        replayKitChannel = FlutterMethodChannel(name: "io.livekit.example.flutter/replaykit-channel", binaryMessenger: controller.binaryMessenger)
        voipChannel = FlutterMethodChannel(name: "top.hangxun.app/voip", binaryMessenger: controller.binaryMessenger)

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
                result(RTCAudioSession.sharedInstance().isAudioEnabled)
            case "bridgeCallKitWebRtcAudio":
                self.bridgeCallKitWebRtcAudio(result: result)
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

        // PushKit must be registered early so VoIP wakes can report CallKit before completion.
        self.registerVoipPush()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Required empty hook so Getui can receive remote notifications when the app is backgrounded.
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }

    // MARK: - CallkitIncomingAppDelegate (required by flutter_callkit_incoming)

    /// Dart handles accept via FlutterCallkitIncoming.onEvent — fulfill so CallKit activates audio.
    func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
        NSLog("HangXun CallKit: onAccept room=%@", call.data.uuid)
        // Configure category BEFORE fulfill so CallKit can activate session on lock screen.
        // Do NOT setActive here — CallKit owns activation (didActivateAudioSession).
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            emitAudioDebug("CallKit onAccept category configured room=\(call.data.uuid)")
        } catch {
            emitAudioDebug("CallKit onAccept category failed \(error.localizedDescription)")
        }
        action.fulfill()
    }

    func onDecline(_ call: Call, _ action: CXEndCallAction) {
        NSLog("HangXun CallKit: onDecline room=%@", call.data.uuid)
        action.fulfill()
    }

    func onEnd(_ call: Call, _ action: CXEndCallAction) {
        NSLog("HangXun CallKit: onEnd room=%@", call.data.uuid)
        action.fulfill()
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
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        emitAudioDebug("CallKit audio session activated isAudioEnabled=true")
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onCallKitAudioActivated", arguments: nil)
        }
    }

    func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        emitAudioDebug("CallKit audio session deactivated isAudioEnabled=false")
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onCallKitAudioDeactivated", arguments: nil)
        }
    }

    // MARK: - WebRTC audio (in-app calls — useManualAudio requires explicit enable)

    private func enableWebRtcAudio(preferSpeaker: Bool, result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        do {
            var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
            if preferSpeaker {
                options.insert(.defaultToSpeaker)
            }
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try session.setActive(true)
            RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
            RTCAudioSession.sharedInstance().isAudioEnabled = true
            emitAudioDebug("in-app audio enabled speaker=\(preferSpeaker)")
            result(true)
        } catch {
            emitAudioDebug("in-app enable failed \(error.localizedDescription)")
            result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
        }
    }

    private func disableWebRtcAudio(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(session)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        emitAudioDebug("in-app audio disabled")
        result(true)
    }

    /// CallKit already activated AVAudioSession — bridge WebRTC without reconfiguring.
    private func bridgeCallKitWebRtcAudio(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        emitAudioDebug("CallKit bridge (no setActive) isAudioEnabled=true")
        result(true)
    }

    // MARK: - PushKit (VoIP)

    private func registerVoipPush() {
        let registry = PKPushRegistry(queue: DispatchQueue.main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry
        NSLog("HangXun VoIP: PKPushRegistry registered")
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
        NSLog("HangXun VoIP token: %@", deviceToken)

        HangXunGetuiVoip.registerPushKitToken(credentials.token)

        UserDefaults.standard.set(deviceToken, forKey: "DevicePushTokenVoIP")
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)

        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onVoipToken", arguments: deviceToken)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
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

    private func endCallKitCalls(roomID: String) {
        let endData = flutter_callkit_incoming.Data(args: [
            "id": roomID,
            "nameCaller": "",
            "handle": "",
            "type": 0,
        ])
        let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance
        plugin?.endCall(endData)
    }

    private func notifyDartVoipRemoteEnd(roomID: String, action: String) {
        DispatchQueue.main.async {
            self.voipChannel?.invokeMethod("onVoipRemoteEnd", arguments: [
                "roomID": roomID,
                "action": action,
            ])
        }
    }

    /// iOS 13+: MUST report CallKit incoming call before invoking completion.
    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        let dict = flattenVoipPayload(payload.dictionaryPayload)
        NSLog("HangXun VoIP payload (flat): %@", dict)

        HangXunGetuiVoip.handlePushKitPayload(dict)

        let action = ((dict["action"] as? String) ?? "").lowercased()
        let roomID = (dict["roomID"] as? String)
            ?? (dict["callUUID"] as? String)
            ?? (dict["id"] as? String)
            ?? UUID().uuidString

        if action == "cancel" || action == "end" || action == "hungup" || action == "reject" {
            NSLog("HangXun VoIP remote end action=%@ room=%@", action, roomID)
            endCallKitCalls(roomID: roomID)
            notifyDartVoipRemoteEnd(roomID: roomID, action: action)
            DispatchQueue.main.async { completion() }
            return
        }

        if UIApplication.shared.applicationState == .active {
            NSLog("HangXun VoIP: skip CallKit (app foreground, room=%@)", roomID)
            DispatchQueue.main.async { completion() }
            return
        }

        let mediaType = (dict["mediaType"] as? String) ?? "audio"
        let isVideo = mediaType == "video"
        let nameCaller = (dict["nickname"] as? String)
            ?? (dict["inviterNickname"] as? String)
            ?? (dict["nameCaller"] as? String)
            ?? "来电"
        let handle = (dict["inviterUserID"] as? String)
            ?? (dict["handle"] as? String)
            ?? ""

        var info: [String: Any?] = [:]
        info["id"] = roomID
        info["nameCaller"] = nameCaller
        info["appName"] = "航讯"
        info["handle"] = handle
        info["type"] = isVideo ? 1 : 0
        var timeoutSec = 30
        if let t = dict["timeout"] as? Int {
            timeoutSec = t
        } else if let t = dict["timeout"] as? String, let v = Int(t) {
            timeoutSec = v
        } else if let t = dict["timeout"] as? Double {
            timeoutSec = Int(t)
        }
        if timeoutSec <= 0 { timeoutSec = 30 }
        info["duration"] = timeoutSec * 1000
        info["extra"] = dict

        let data = flutter_callkit_incoming.Data(args: info)
        // Let CallKit activate session; WebRTC bridges in didActivateAudioSession.
        data.configureAudioSession = false
        data.audioSessionActive = false
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion()
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
