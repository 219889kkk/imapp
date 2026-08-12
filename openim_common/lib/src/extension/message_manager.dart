import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

extension MessageManagerExt on MessageManager {
  Future<Message> createCustomEmojiMessage({
    required String url,
    int? width,
    int? height,
  }) =>
      createCustomMessage(
        data: json.encode({
          "customType": CustomMessageType.emoji,
          "data": {
            'url': url,
            'width': width,
            'height': height,
          },
        }),
        extension: '',
        description: '',
      );

  Future<Message> createFailedHintMessage({required int type}) =>
      createCustomMessage(
        data: json.encode({
          "customType": type,
          "data": {},
        }),
        extension: '',
        description: '',
      );
}

extension MessageExt on Message {
  bool get isDeletedByFriendType {
    if (isCustomType) {
      try {
        var map = json.decode(customElem!.data!);
        var customType = map['customType'];
        return CustomMessageType.deletedByFriend == customType;
      } catch (e, s) {
        Logger.print('$e $s');
      }
    }
    return false;
  }

  bool get isBlockedByFriendType {
    if (isCustomType) {
      try {
        var map = json.decode(customElem!.data!);
        var customType = map['customType'];
        return CustomMessageType.blockedByFriend == customType;
      } catch (e, s) {
        Logger.print('$e $s');
      }
    }
    return false;
  }

  bool get isEmojiType {
    if (isCustomType) {
      try {
        var map = json.decode(customElem!.data!);
        var customType = map['customType'];
        return CustomMessageType.emoji == customType;
      } catch (e, s) {
        Logger.print('$e $s');
      }
    }
    return false;
  }

  bool get isTextType => contentType == MessageType.text;

  bool get isPictureType => contentType == MessageType.picture;

  bool get isVoiceType => contentType == MessageType.voice;

  bool get isVideoType => contentType == MessageType.video;

  bool get isFileType => contentType == MessageType.file;

  bool get isMergerType => contentType == MessageType.merger;

  bool get isLocationType => contentType == MessageType.location;

  bool get isCardType => contentType == MessageType.card;

  bool get isCustomFaceType => contentType == MessageType.customFace;

  bool get isCustomType => contentType == MessageType.custom;

  /// Local call history bubble (customType 901), not RTC signaling packets.
  bool get isCallRecordType {
    if (!isCustomType) return false;
    try {
      final map = json.decode(customElem!.data!);
      return map['customType'] == CustomMessageType.call;
    } catch (_) {
      return false;
    }
  }

  /// Answered / hung-up call record — keep history, never count as unread.
  bool get isAnsweredCallRecordType {
    if (!isCustomType) return false;
    try {
      final map = json.decode(customElem!.data!);
      final customType = map['customType'];
      if (customType == CustomMessageType.callingAccept ||
          customType == CustomMessageType.callingHungup) {
        return true;
      }
      if (customType != CustomMessageType.call) return false;
      final data = map['data'];
      final state = data is Map ? data['state']?.toString() ?? '' : '';
      return state == 'hangup' ||
          state == 'beHangup' ||
          state == 'calling' ||
          state == 'beAccepted';
    } catch (_) {
      return false;
    }
  }

  /// RTC signaling messages (invite/accept/reject/cancel/hangup).
  /// They should not render as normal chat bubbles.
  bool get isCallingSignalingType {
    if (!isCustomType) return false;
    try {
      final map = json.decode(customElem!.data!);
      final customType = map['customType'];
      return customType == CustomMessageType.callingInvite ||
          customType == CustomMessageType.callingAccept ||
          customType == CustomMessageType.callingReject ||
          customType == CustomMessageType.callingCancel ||
          customType == CustomMessageType.callingHungup;
    } catch (_) {
      return false;
    }
  }

  bool get isRevokeType => contentType == MessageType.revokeMessageNotification;

  bool get isNotificationType => contentType! >= 1000;
}

class CustomMessageType {
  static const callingInvite = 200;
  static const callingAccept = 201;
  static const callingReject = 202;
  static const callingCancel = 203;
  static const callingHungup = 204;

  static const call = 901;
  static const emoji = 902;
  static const tag = 903;
  static const moments = 904;
  static const meeting = 905;
  static const blockedByFriend = 910;
  static const deletedByFriend = 911;
  static const removedFromGroup = 912;
  static const groupDisbanded = 913;
}

extension PublicUserInfoExt on PublicUserInfo {
  UserInfo get simpleUserInfo {
    return UserInfo(userID: userID, nickname: nickname, faceURL: faceURL);
  }
}

extension FriendInfoExt on FriendInfo {
  UserInfo get simpleUserInfo {
    return UserInfo(userID: userID, nickname: nickname, faceURL: faceURL);
  }
}
