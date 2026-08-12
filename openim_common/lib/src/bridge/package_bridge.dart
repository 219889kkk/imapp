import 'package:flutter/material.dart';

import '../models/signaling_info.dart';

class PackageBridge {
  PackageBridge._();

  static SelectContactsBridge? selectContactsBridge;
  static ViewUserProfileBridge? viewUserProfileBridge;
  static ScanBridge? scanBridge;
  static RTCBridge? rtcBridge;

  /// Clears the local incoming-call notification (registered by app layer).
  static VoidCallback? clearCallNotification;

  /// Handles Accept/Reject on the local incoming-call notification.
  /// `true` = accept / pick up, `false` = reject.
  static void Function(bool accept)? handleCallNotificationAction;

  /// CallKit Accept with reconstructed [SignalingInfo] (iOS VoIP path).
  static void Function(SignalingInfo signaling)? onCallKitAccept;

  /// CallKit Decline with reconstructed [SignalingInfo] (iOS VoIP path).
  static void Function(SignalingInfo signaling)? onCallKitDecline;

  /// CallKit / system End during active call (lock-screen hangup).
  /// Ringing timeout is [onCallKitTimeout] — do not treat as reject.
  static void Function(SignalingInfo? signaling)? onCallKitEnded;

  /// CallKit ring timed out (missed) — local cleanup only, never send reject.
  static void Function(SignalingInfo? signaling)? onCallKitTimeout;

  /// PushKit remote cancel/hungup (native endCall before Dart WS).
  static void Function(String? roomID, String action)? onVoipRemoteEnd;

  /// iOS CallKit activated AVAudioSession — WebRTC may now capture/play.
  static VoidCallback? onCallKitAudioActivated;

  /// iOS CallKit deactivated AVAudioSession — may need in-app re-enable if still in call.
  static VoidCallback? onCallKitAudioDeactivated;

  /// iOS: ignore spurious CallKit `ended` after programmatic dismiss.
  static void Function(String? roomID)? suppressCallKitEnded;

  /// True when [roomID] was cancelled/hung up recently — ignore late invites.
  static bool Function(String? roomID)? isCallRoomEnded;

  /// 1:1 call: remote participant left the LiveKit room (peer hangup).
  static void Function(String? roomID)? onPeerLeftCall;

  /// Caller: remote joined LiveKit while waiting — cancel ring timeout / start in-call UI.
  static void Function(String? roomID)? markOutboundPeerPresent;

  /// HTTP/WS endpoint switched (primary ↔ backup). App should reinit IM SDK.
  static Future<void> Function()? onEndpointSwitched;

  /// Wall-clock seconds since the active call was answered (0 if not connected).
  static int Function()? connectedCallDurationSec;
}

abstract class ScanBridge {
  scanOutUserID(String userID);

  scanOutGroupID(String groupID);
}

abstract class OrganizationMultiSelBridge {
  Widget get checkedConfirmView;

  bool get isMultiModel;

  bool isChecked(dynamic info);

  bool isDefaultChecked(dynamic info);

  Function()? onTap(dynamic info);

  toggleChecked(dynamic info);

  removeItem(dynamic info);

  updateDefaultCheckedList(List<String> userIDList);
}

abstract class ViewUserProfileBridge {
  viewUserProfile(
    String userID,
    String? nickname,
    String? faceURL, [
    String? groupID,
  ]);
}

abstract class SelectContactsBridge {
  Future<T?>? selectContacts<T>(
    int type, {
    List<String>? defaultCheckedIDList,
    List<dynamic>? checkedList,
    List<String>? excludeIDList,
    bool openSelectedSheet = false,
    String? groupID,
    String? ex,
  });
}

abstract class RTCBridge {
  bool get hasConnection;
  bool get hasCallOverlay;
  void dismiss();
}

class GetTags {
  static final List<String> _chatTags = <String>[];
  static final List<String> _userProfileTags = <String>[];

  static void createChatTag() {
    _chatTags.add('_${DateTime.now().millisecondsSinceEpoch}');
  }

  static void createUserProfileTag() {
    _userProfileTags.add('_${DateTime.now().millisecondsSinceEpoch}');
  }

  static void destroyChatTag() {
    _chatTags.removeLast();
  }

  static void destroyUserProfileTag() {
    _userProfileTags.removeLast();
  }

  static String? get chat => _chatTags.isNotEmpty ? _chatTags.last : null;

  static String get userProfile => _userProfileTags.last;
}
