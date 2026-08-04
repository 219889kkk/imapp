import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            let userInfo = request.content.userInfo
            let isCall = Self.isCallPush(userInfo: userInfo,
                                         title: bestAttemptContent.title,
                                         body: bestAttemptContent.body)
            if isCall {
                let isVideo = Self.isVideoCall(userInfo: userInfo,
                                               title: bestAttemptContent.title,
                                               body: bestAttemptContent.body)
                // Keep server title/body when already call-styled; otherwise enforce call look.
                if bestAttemptContent.title.isEmpty ||
                    !(bestAttemptContent.title.contains("通话") ||
                      bestAttemptContent.title.lowercased().contains("call")) {
                    bestAttemptContent.title = isVideo ? "视频通话" : "语音通话"
                }
                if #available(iOSApplicationExtension 15.0, *) {
                    bestAttemptContent.interruptionLevel = .timeSensitive
                }
                // Prefer custom call sound when bundled; otherwise system default.
                if Bundle.main.url(forResource: "call", withExtension: "caf") != nil {
                    bestAttemptContent.sound = UNNotificationSound(named: .init(rawValue: "call.caf"))
                } else {
                    bestAttemptContent.sound = .default
                }
            } else if let clientID = userInfo["clientMsgID"] as? String, !clientID.isEmpty {
                UserDefaults.standard.set(request.identifier, forKey: "key")
            }
            contentHandler(bestAttemptContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private static func isCallPush(userInfo: [AnyHashable: Any], title: String, body: String) -> Bool {
        let blob = "\(title)\(body)\(stringify(userInfo))".lowercased()
        if blob.contains("callinginvite") { return true }
        if title.contains("通话") || body.contains("通话") { return true }
        if blob.contains("voice call") || blob.contains("video call") { return true }
        if body.contains("邀请你语音") || body.contains("邀请你视频") { return true }
        return false
    }

    private static func isVideoCall(userInfo: [AnyHashable: Any], title: String, body: String) -> Bool {
        let blob = "\(title)\(body)\(stringify(userInfo))".lowercased()
        return blob.contains("video") || blob.contains("视频")
    }

    private static func stringify(_ userInfo: [AnyHashable: Any]) -> String {
        if let ex = userInfo["ex"] as? String { return ex }
        if let payload = userInfo["payload"] as? String { return payload }
        return "\(userInfo)"
    }
}
