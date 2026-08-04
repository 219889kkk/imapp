import UIKit
import Flutter
import FirebaseCore
import PushKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
    
    var replayKitChannel: FlutterMethodChannel! = nil
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
        
        replayKitChannel = FlutterMethodChannel(name: "io.livekit.example.flutter/replaykit-channel",binaryMessenger: controller.binaryMessenger)
        
        replayKitChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping  FlutterResult)  -> Void in
            self.handleReplayKitFromFlutter(result: result, call:call)
        })
        
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

        // Getui: bindAlias (Dart) + registerVoipTokenCredentials (native) for kill-app wake.
        HangXunGetuiVoip.registerVoipTokenCredentials(credentials.token)

        // flutter_callkit_incoming stores token for Dart getDevicePushTokenVoIP().
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        NSLog("HangXun VoIP: token invalidated")
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
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

        let dict = payload.dictionaryPayload
        NSLog("HangXun VoIP payload: %@", dict)

        HangXunGetuiVoip.handleVoipNotification(dict)

        let action = ((dict["action"] as? String) ?? "").lowercased()
        let roomID = (dict["roomID"] as? String)
            ?? (dict["id"] as? String)
            ?? UUID().uuidString

        if action == "cancel" || action == "end" || action == "hungup" || action == "reject" {
            let endData = flutter_callkit_incoming.Data(args: [
                "id": roomID,
                "nameCaller": "",
                "handle": "",
                "type": 0,
            ])
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(endData)
            DispatchQueue.main.async { completion() }
            return
        }

        let mediaType = (dict["mediaType"] as? String) ?? "audio"
        let isVideo = mediaType == "video"
        let nameCaller = (dict["nickname"] as? String)
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
        info["duration"] = 60000
        info["extra"] = dict

        let data = flutter_callkit_incoming.Data(args: info)
        // Hard requirement: reportNewIncomingCall via plugin before completion returns.
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion()
        }
    }
    
    func handleReplayKitFromFlutter(result:FlutterResult, call: FlutterMethodCall){
        switch (call.method) {
        case "startReplayKit":
            self.hasEmittedFirstSample = false
            let group=UserDefaults(suiteName: "group.io.livekit.example.flutter")
            group!.set(false, forKey: "closeReplayKitFromNative")
            group!.set(false, forKey: "closeReplayKitFromFlutter")
            self.observeReplayKitStateChanged()
            break
        case "closeReplayKit":
            let group=UserDefaults(suiteName: "group.io.livekit.example.flutter")
            group!.set(true,forKey: "closeReplayKitFromFlutter")
            result(true)
            break
        default:
            return result(FlutterMethodNotImplemented)
        }
    }
    

    func observeReplayKitStateChanged(){
        if (self.observeTimer != nil) {
            return
        }
        
        let group=UserDefaults(suiteName: "group.io.livekit.example.flutter")
        self.observeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { (timer) in
            let closeReplayKitFromNative=group!.bool(forKey: "closeReplayKitFromNative")
            let hasSampleBroadcast=group!.bool(forKey: "hasSampleBroadcast")
            
            if (closeReplayKitFromNative) {
                self.hasEmittedFirstSample = false
                self.replayKitChannel.invokeMethod("closeReplayKitFromNative", arguments: true)
            } else if (hasSampleBroadcast) {
                if (!self.hasEmittedFirstSample) {
                    self.hasEmittedFirstSample = true
                    self.replayKitChannel.invokeMethod("hasSampleBroadcast", arguments: true)
                }
            }
        }
    }
}
