import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_live_alert/flutter_openim_live_alert.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../openim_live.dart';

mixin OpenIMLive {
  final signalingSubject = PublishSubject<CallEvent>();

  void invitationCancelled(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beCanceled, info));
  }

  void inviteeAccepted(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beAccepted, info));
  }

  void inviteeRejected(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beRejected, info));
  }

  void receiveNewInvitation(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beCalled, info));
  }

  void beHangup(SignalingInfo info) {
    signalingSubject.add(CallEvent(CallState.beHangup, info));
  }

  final backgroundSubject = PublishSubject<bool>();

  final insertSignalingMessageSubject = PublishSubject<CallEvent>();

  Function(SignalingMessageEvent)? onSignalingMessage;
  final roomParticipantDisconnectedSubject = PublishSubject<RoomCallingInfo>();
  final roomParticipantConnectedSubject = PublishSubject<RoomCallingInfo>();

  bool _isRunningBackground = false;

  CallEvent? _beCalledEvent;

  bool _autoPickup = false;

  final _ring = 'assets/audio/live_ring.wav';
  final _audioPlayer = AudioPlayer(
    // Avoid fighting LiveKit's playAndRecord session (reduces connect-time noise).
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
    handleAudioSessionActivation: false,
  );

  bool get isBusy => OpenIMLiveClient().isBusy;

  onCloseLive() {
    signalingSubject.close();
    backgroundSubject.close();
    roomParticipantDisconnectedSubject.close();
    roomParticipantConnectedSubject.close();
    _stopSound();
  }

  onInitLive() async {
    _signalingListener();
    _insertSignalingMessageListener();
    _bindLiveAlertButtons();
    backgroundSubject.listen((background) {
      _isRunningBackground = background;
      if (!_isRunningBackground) {
        FlutterOpenimLiveAlert.closeLiveAlert();
        if (_beCalledEvent != null) {
          final pending = _beCalledEvent!;
          _beCalledEvent = null;
          signalingSubject.add(pending);
        }
      }
    });

    roomParticipantDisconnectedSubject.listen((info) {
      if (null == info.participant || info.participant!.length == 1) {
        OpenIMLiveClient().closeByRoomID(info.invitation!.roomID!);
      }
    });
  }

  void _bindLiveAlertButtons() {
    FlutterOpenimLiveAlert.buttonEvent(
      activityName: 'io.openim.MainActivity',
      onAccept: () {
        // Keep pending invite; returning to foreground will present the call UI.
        _autoPickup = true;
      },
      onReject: () {
        final pending = _beCalledEvent;
        _beCalledEvent = null;
        _stopSound();
        PackageBridge.clearCallNotification?.call();
        if (pending != null) {
          onTapReject(pending.data..userID = OpenIM.iMManager.userID);
        }
      },
    );
  }

  Stream<CallEvent> get _stream => signalingSubject
      .stream /*.where((event) => LiveClient.dispatchSignaling(event))*/;

  _signalingListener() => _stream.listen(
        (event) async {
          if (event.state != CallState.beCalled) {
            _beCalledEvent = null;
            FlutterOpenimLiveAlert.closeLiveAlert();
            PackageBridge.clearCallNotification?.call();
          }
          if (event.state == CallState.beCalled) {
            _playSound();
            final mediaType = event.data.invitation!.mediaType;
            final sessionType = event.data.invitation!.sessionType;
            final callType =
                mediaType == 'audio' ? CallType.audio : CallType.video;
            final callObj = sessionType == ConversationType.single
                ? CallObj.single
                : CallObj.group;

            if (_isRunningBackground) {
              _beCalledEvent = event;
              if (Platform.isAndroid) {
                final hasOverlay = await Permissions.checkSystemAlertWindow();
                if (!hasOverlay) {
                  await Permissions.request([Permission.systemAlertWindow]);
                }
                await FlutterOpenimLiveAlert.showLiveAlert(
                  title: callType == CallType.video
                      ? StrRes.videoCallInviteHint
                      : StrRes.voiceCallInviteHint,
                  rejectText: StrRes.reject,
                  acceptText: StrRes.pickUp,
                );
              }
              // iOS / no-overlay: keep pending invite and show UI when app returns.
              return;
            }
            _beCalledEvent = null;
            final overlayContext = Get.overlayContext;
            if (overlayContext == null) {
              _beCalledEvent = event;
              return;
            }
            OpenIMLiveClient().start(
              overlayContext,
              callEventSubject: signalingSubject,
              roomID: event.data.invitation!.roomID!,
              inviteeUserIDList: event.data.invitation!.inviteeUserIDList!,
              inviterUserID: event.data.invitation!.inviterUserID!,
              groupID: event.data.invitation!.groupID,
              callType: callType,
              callObj: callObj,
              initState: CallState.beCalled,
              onSyncUserInfo: onSyncUserInfo,
              onSyncGroupInfo: onSyncGroupInfo,
              onSyncGroupMemberInfo: onSyncGroupMemberInfo,
              autoPickup: _autoPickup,
              onTapPickup: () => onTapPickup(
                event.data..userID = OpenIM.iMManager.userID,
              ),
              onTapReject: () => onTapReject(
                event.data..userID = OpenIM.iMManager.userID,
              ),
              onTapHangup: (duration, isPositive) => onTapHangup(
                event.data..userID = OpenIM.iMManager.userID,
                duration,
                isPositive,
              ),
              onError: onError,
              onRoomDisconnected: () => onRoomDisconnected(event.data),
            );
          } else if (event.state == CallState.beRejected) {
            insertSignalingMessageSubject.add(event);
            _stopSound();
          } else if (event.state == CallState.beHangup) {
            _stopSound();
          } else if (event.state == CallState.beCanceled) {
            insertSignalingMessageSubject.add(event);
            _stopSound();
          } else if (event.state == CallState.beAccepted) {
            _stopSound();
          } else if (event.state == CallState.otherReject ||
              event.state == CallState.otherAccepted) {
            _stopSound();
          } else if (event.state == CallState.timeout) {
            insertSignalingMessageSubject.add(event);

            _stopSound();
            final sessionType = event.data.invitation!.sessionType;

            if (sessionType == 1) {
              onTimeoutCancelled(event.data);
            }
          }
        },
      );

  _insertSignalingMessageListener() {
    insertSignalingMessageSubject.listen((value) {
      _insertMessage(
        state: value.state,
        signalingInfo: value.data,
        duration: value.fields ?? 0,
      );
    });
  }

  call({
    required CallObj callObj,
    required CallType callType,
    CallState callState = CallState.call,
    String? roomID,
    String? inviterUserID,
    required List<String> inviteeUserIDList,
    String? groupID,
    SignalingCertificate? credentials,
  }) async {
    final mediaType = callType == CallType.audio ? 'audio' : 'video';
    final sessionType = callObj == CallObj.single ? 1 : 3;
    inviterUserID ??= OpenIM.iMManager.userID;

    final signal = SignalingInfo(
      userID: inviterUserID,
      invitation: InvitationInfo(
        inviterUserID: inviterUserID,
        inviteeUserIDList: inviteeUserIDList,
        roomID: roomID ?? groupID ?? const Uuid().v4(),
        timeout: 30,
        mediaType: mediaType,
        sessionType: sessionType,
        platformID: IMUtils.getPlatform(),
        groupID: groupID,
      ),
    );

    OpenIMLiveClient().start(
      Get.overlayContext!,
      callEventSubject: signalingSubject,
      inviterUserID: inviterUserID,
      groupID: groupID,
      inviteeUserIDList: inviteeUserIDList,
      callObj: callObj,
      callType: callType,
      initState: callState,
      onDialSingle: () => onDialSingle(signal),
      onDialGroup: () => onDialGroup(signal),
      onJoinGroup: () => Future.value(credentials!),
      onTapCancel: () => onTapCancel(signal),
      onTapHangup: (duration, isPositive) => onTapHangup(
        signal,
        duration,
        isPositive,
      ),
      onSyncUserInfo: onSyncUserInfo,
      onSyncGroupInfo: onSyncGroupInfo,
      onSyncGroupMemberInfo: onSyncGroupMemberInfo,
      onWaitingAccept: () {
        if (callObj == CallObj.single) _playSound();
      },
      onBusyLine: onBusyLine,
      onStartCalling: () {
        _stopSound();
      },
      onError: onError,
      onRoomDisconnected: () => onRoomDisconnected(signal),
      onClose: _stopSound,
    );
  }

  onError(error, stack) {
    Logger.print('onError=====> $error $stack');
    OpenIMLiveClient().close();
    _stopSound();
    if (error is PlatformException) {
      if (int.parse(error.code) == SDKErrorCode.hasBeenBlocked) {
        IMViews.showToast(StrRes.callFail);
        return;
      }
    }
    IMViews.showToast(StrRes.networkError);
  }

  onRoomDisconnected(SignalingInfo signalingInfo) {}

  Future<SignalingCertificate> onDialSingle(SignalingInfo signaling) async {
    final data = {
      'customType': CustomMessageType.callingInvite,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final isVideo = signaling.invitation!.mediaType == 'video';
    OpenIM.iMManager.messageManager.sendMessage(
      message: message,
      offlinePushInfo: Config.offlineCallPushInfo(isVideo: isVideo),
      userID: signaling.invitation!.inviteeUserIDList!.first,
      // Keep WS delivery when online; also allow offline push when away.
      isOnlineOnly: false,
    );
    final certificate = await Apis.getTokenForRTC(
        signaling.invitation!.roomID!, OpenIM.iMManager.userID);

    return certificate;
  }

  Future<SignalingCertificate> onDialGroup(SignalingInfo signaling) async {
    final data = {
      'customType': CustomMessageType.callingInvite,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final isVideo = signaling.invitation!.mediaType == 'video';
    for (final userID in signaling.invitation!.inviteeUserIDList!) {
      OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: Config.offlineCallPushInfo(isVideo: isVideo),
        userID: userID,
        isOnlineOnly: false,
      );
    }
    final certificate = await Apis.getTokenForRTC(
      signaling.invitation!.roomID!,
      OpenIM.iMManager.userID,
    );

    return certificate;
  }

  Future<SignalingCertificate> onTapPickup(SignalingInfo signaling) async {
    _beCalledEvent = null; // ios bug
    _autoPickup = false;
    _stopSound();
    final data = {
      'customType': CustomMessageType.callingAccept,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: signaling.invitation!.inviterUserID,
        isOnlineOnly: true);
    final certificate = await Apis.getTokenForRTC(
        signaling.invitation!.roomID!, OpenIM.iMManager.userID);

    return certificate;
  }

  onTapReject(SignalingInfo signaling) async {
    _stopSound();
    insertSignalingMessageSubject.add(CallEvent(CallState.reject, signaling));

    final data = {
      'customType': CustomMessageType.callingReject,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final recvUserID =
        signaling.invitation!.inviterUserID == OpenIM.iMManager.userID
            ? signaling.invitation!.inviteeUserIDList!.first
            : signaling.invitation!.inviterUserID;
    return OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: recvUserID,
        isOnlineOnly: true);
  }

  onTapCancel(SignalingInfo signaling) async {
    _stopSound();
    insertSignalingMessageSubject.add(CallEvent(CallState.cancel, signaling));

    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');
    final recvUserIDList = _recvUserIDList(signaling);
    for (final userID in recvUserIDList) {
      OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          offlinePushInfo: OfflinePushInfo(),
          userID: userID,
          isOnlineOnly: true);
    }
    return true;
  }

  onTimeoutCancelled(SignalingInfo signaling) async {
    final data = {
      'customType': CustomMessageType.callingCancel,
      'data': signaling.invitation!.toJson()
    };
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode(data), extension: '', description: '');

    OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: signaling.invitation!.inviterUserID,
        isOnlineOnly: true);

    return true;
  }

  onTapHangup(SignalingInfo signaling, int duration, bool isPositive) async {
    if (isPositive) {
      final data = {
        'customType': CustomMessageType.callingHungup,
        'data': signaling.invitation!.toJson()
      };
      final message = await OpenIM.iMManager.messageManager.createCustomMessage(
          data: jsonEncode(data), extension: '', description: '');
      final recvUserIDList = _recvUserIDList(signaling);
      for (final userID in recvUserIDList) {
        OpenIM.iMManager.messageManager.sendMessage(
            message: message,
            offlinePushInfo: OfflinePushInfo(),
            userID: userID,
            isOnlineOnly: true);
      }
    }
    _stopSound();

    insertSignalingMessageSubject.add(CallEvent(
      CallState.hangup,
      signaling,
      fields: duration,
    ));
  }

  onBusyLine() {
    _stopSound();
    IMViews.showToast(StrRes.busyVideoCallHint);
  }

  onJoin() {}

  Future<UserInfo?> onSyncUserInfo(userID) async {
    var list = await OpenIM.iMManager.userManager.getUsersInfo(
      userIDList: [userID],
    );

    return list.firstOrNull?.simpleUserInfo;
  }

  Future<GroupInfo?> onSyncGroupInfo(groupID) async {
    var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [groupID],
    );
    return list.firstOrNull;
  }

  Future<List<GroupMembersInfo>> onSyncGroupMemberInfo(
      groupID, userIDList) async {
    var list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
      groupID: groupID,
      userIDList: userIDList,
    );
    return list;
  }

  void _playSound() async {
    if (!_audioPlayer.playerState.playing) {
      _audioPlayer.setAsset(_ring, package: 'openim_common');
      _audioPlayer.setLoopMode(LoopMode.one);
      _audioPlayer.setVolume(1.0);
      _audioPlayer.play();
    }
  }

  void _stopSound() async {
    if (_audioPlayer.playerState.playing) {
      _audioPlayer.stop();
    }
  }

  void _insertMessage({
    required CallState state,
    required SignalingInfo signalingInfo,
    int duration = 0,
  }) async {
    (() async {
      var invitation = signalingInfo.invitation;
      var mediaType = invitation!.mediaType;
      var inviterUserID = invitation.inviterUserID;
      var inviteeUserID = invitation.inviteeUserIDList!.first;
      var groupID = invitation.groupID;
      Logger.print(
          'end calling and insert message state:${state.name}, mediaType:$mediaType, inviterUserID:$inviterUserID, inviteeUserID:$inviteeUserID, groupID:$groupID, duration:$duration',
          functionName: '_insertMessage');
      var message = await OpenIM.iMManager.messageManager.createCallMessage(
        state: state.name,
        type: mediaType!,
        duration: duration,
      );

      String? receiverID;
      if (inviterUserID != OpenIM.iMManager.userID) {
        receiverID = inviterUserID;
      } else {
        receiverID = inviteeUserID;
      }

      var msg = await OpenIM.iMManager.messageManager
          .insertSingleMessageToLocalStorage(
        receiverID: inviteeUserID,
        senderID: inviterUserID,
        message: message..status = 2,
      );

      onSignalingMessage?.call(SignalingMessageEvent(msg, 1, receiverID, null));
    })();
  }

  List<String> _recvUserIDList(SignalingInfo signaling) {
    final currentUserID = OpenIM.iMManager.userID;
    final userIDSet = <String>{
      if (signaling.invitation?.inviterUserID != null)
        signaling.invitation!.inviterUserID!,
      ...?signaling.invitation?.inviteeUserIDList,
    };
    userIDSet.remove(currentUserID);
    return userIDSet.toList();
  }
}

class SignalingMessageEvent {
  Message message;
  String? userID;
  String? groupID;
  int sessionType;

  SignalingMessageEvent(
    this.message,
    this.sessionType,
    this.userID,
    this.groupID,
  );

  bool get isSingleChat => sessionType == ConversationType.single;

  bool get isGroupChat =>
      sessionType == ConversationType.group ||
      sessionType == ConversationType.superGroup;
}

extension MessageMangerExt on MessageManager {
  Future<Message> createCallMessage({
    required String type,
    required String state,
    int? duration,
  }) =>
      createCustomMessage(
        data: json.encode({
          "customType": CustomMessageType.call,
          "data": {
            'duration': duration,
            'state': state,
            'type': type,
          },
        }),
        extension: '',
        description: '',
      );
}
