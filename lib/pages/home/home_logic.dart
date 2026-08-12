import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screen_lock/flutter_screen_lock.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../core/controller/session_logout.dart';
import '../../core/im_callback.dart';
import '../../routes/app_navigator.dart';
import '../../widgets/screen_lock_title.dart';

class HomeLogic extends SuperController {
  final pushLogic = Get.find<PushController>();
  final imLogic = Get.find<IMController>();
  final cacheLogic = Get.find<CacheController>();
  final initLogic = Get.find<AppController>();
  final index = 0.obs;
  final unreadMsgCount = 0.obs;
  final unhandledFriendApplicationCount = 0.obs;
  final unhandledGroupApplicationCount = 0.obs;
  final unhandledCount = 0.obs;
  String? _lockScreenPwd;
  bool _isShowScreenLock = false;
  bool? _isAutoLogin;
  final auth = LocalAuthentication();
  final _errorController = PublishSubject<String>();
  var conversationsAtFirstPage = <ConversationInfo>[];

  switchTab(index) {
    this.index.value = index;
  }

  _getUnreadMsgCount() {
    unawaited(_reconcileUnreadMsgCount());
  }

  /// Redis badge can drift after server-side clears; prefer sum of conversation unreads.
  Future<void> _reconcileUnreadMsgCount() async {
    try {
      final sdkStr =
          await OpenIM.iMManager.conversationManager.getTotalUnreadMsgCount();
      final sdkTotal = int.tryParse(sdkStr) ?? 0;
      final listTotal = await _sumConversationUnread();
      final count = listTotal < sdkTotal ? listTotal : sdkTotal;
      if (count != sdkTotal) {
        Logger.print(
            'unread reconcile sdk=$sdkTotal list=$listTotal → $count');
      }
      unreadMsgCount.value = count;
      initLogic.showBadge(count);
    } catch (e, s) {
      Logger.print('reconcileUnread failed: $e $s');
    }
  }

  Future<int> _sumConversationUnread() async {
    var total = 0;
    var offset = 0;
    const page = 200;
    while (true) {
      final chunk = await OpenIM.iMManager.conversationManager
          .getConversationListSplit(offset: offset, count: page);
      if (chunk.isEmpty) break;
      for (final c in chunk) {
        total += c.unreadCount;
      }
      offset += chunk.length;
      if (chunk.length < page) break;
      // Safety: avoid infinite loops on huge accounts.
      if (offset > 5000) break;
    }
    return total;
  }

  /// Called when conversation list is ready — clamp tab badge to list reality.
  void applyConversationUnreadSum(int listTotal) {
    if (listTotal < 0) return;
    if (listTotal < unreadMsgCount.value) {
      Logger.print(
          'unread clamp from list $listTotal (was ${unreadMsgCount.value})');
      unreadMsgCount.value = listTotal;
      initLogic.showBadge(listTotal);
    }
  }

  Future<void> getUnhandledFriendApplicationCount() async {
    var i = 0;
    var list = await OpenIM.iMManager.friendshipManager.getFriendApplicationListAsRecipient();
    var haveReadList = DataSp.getHaveReadUnHandleFriendApplication();
    haveReadList ??= <String>[];
    for (var info in list) {
      var id = IMUtils.buildFriendApplicationID(info);
      if (!haveReadList.contains(id)) {
        if (info.handleResult == 0) i++;
      }
    }
    unhandledFriendApplicationCount.value = i;
    unhandledCount.value = unhandledGroupApplicationCount.value + i;
  }

  Future<void> getUnhandledGroupApplicationCount() async {
    var i = 0;
    var list = await OpenIM.iMManager.groupManager.getGroupApplicationListAsRecipient();
    var haveReadList = DataSp.getHaveReadUnHandleGroupApplication();
    haveReadList ??= <String>[];
    for (var info in list) {
      var id = IMUtils.buildGroupApplicationID(info);
      if (!haveReadList.contains(id)) {
        if (info.handleResult == 0) i++;
      }
    }
    unhandledGroupApplicationCount.value = i;
    unhandledCount.value = unhandledFriendApplicationCount.value + i;
  }

  @override
  void onInit() {
    _isAutoLogin = Get.arguments != null ? Get.arguments['isAutoLogin'] : false;
    LoadingView.singleton.dismiss();
    EasyLoading.dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LoadingView.singleton.dismiss();
      EasyLoading.dismiss();
    });
    if (_isAutoLogin == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLockScreenPwd());
    }
    if (Get.arguments != null) {
      conversationsAtFirstPage = Get.arguments['conversations'] ?? [];
    }
    imLogic.unreadMsgCountEventSubject.listen((value) {
      unreadMsgCount.value = value;
      initLogic.showBadge(value);
    });
    imLogic.friendApplicationChangedSubject.listen((value) {
      getUnhandledFriendApplicationCount();
    });
    imLogic.groupApplicationChangedSubject.listen((value) {
      getUnhandledGroupApplicationCount();
    });

    imLogic.imSdkStatusPublishSubject.listen((value) {
      if (value.status == IMSdkStatus.syncEnded) {
        imLogic.recoverPendingRtcInvitations();
      }
    });

    super.onInit();
  }

  @override
  void onReady() {
    EasyLoading.dismiss();
    imLogic.recoverPendingRtcInvitations();
    _getUnreadMsgCount();
    getUnhandledFriendApplicationCount();
    getUnhandledGroupApplicationCount();
    cacheLogic.initCallRecords();
    _subscribeFriendsOnlineStatus();
    super.onReady();
  }

  /// Subscribe friends' online status so last-online timestamps can be cached
  /// when they go offline after this session starts.
  void _subscribeFriendsOnlineStatus() async {
    try {
      final friends =
          await OpenIM.iMManager.friendshipManager.getFriendListMap();
      final ids = <String>[];
      for (final item in friends) {
        if (item is Map && item['userID'] != null) {
          ids.add(item['userID'].toString());
        } else if (item is FriendInfo && item.userID != null) {
          ids.add(item.userID!);
        }
      }
      if (ids.isEmpty) return;
      // SDK subscription limit is 3000; keep a safe batch.
      await OpenIM.iMManager.userManager
          .subscribeUsersStatus(ids.take(500).toList());
    } catch (e, s) {
      Logger.print('subscribe friends status failed: $e $s');
    }
  }

  @override
  void onClose() {
    _errorController.close();
    super.onClose();
  }

  _localAuth() async {
    final didAuthenticate = await IMUtils.checkingBiometric(auth);
    if (didAuthenticate) {
      Get.back();
    }
  }

  _showLockScreenPwd() async {
    if (_isShowScreenLock) return;
    _lockScreenPwd = DataSp.getLockScreenPassword();
    if (null != _lockScreenPwd) {
      final context = Get.context;
      if (context == null) return;
      final isEnabledBiometric = DataSp.isEnabledBiometric() == true;
      bool enabled = false;
      if (isEnabledBiometric) {
        final isSupportedBiometrics = await auth.isDeviceSupported();
        final canCheckBiometrics = await auth.canCheckBiometrics;
        enabled = isSupportedBiometrics && canCheckBiometrics;
      }
      _isShowScreenLock = true;
      screenLock(
        context: context,
        correctString: _lockScreenPwd!,
        maxRetries: 3,
        title: ScreenLockTitle(stream: _errorController.stream),
        canCancel: false,
        customizedButtonChild: enabled ? const Icon(Icons.fingerprint) : null,
        customizedButtonTap: enabled ? () async => await _localAuth() : null,
        onUnlocked: () {
          _isShowScreenLock = false;
          Get.back();
        },
        onMaxRetries: (_) async {
          Get.back();
          await LoadingView.singleton.wrap(asyncFunction: () async {
            await SessionLogout.run(
              im: imLogic,
              onConversationsCleared: () => conversationsAtFirstPage.clear(),
            );
            await DataSp.clearLockScreenPassword();
            await DataSp.closeBiometric();
          });
          AppNavigator.startLogin();
        },
        onError: (retries) {
          _errorController.sink.add(
            retries.toString(),
          );
        },
      );
    }
  }

  @override
  void onDetached() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {}

  @override
  void onResumed() {
    // Foreground after offline: drop stale lock-screen rings / timers.
    imLogic.recoverPendingRtcInvitations();
  }

  @override
  void onHidden() {}
}
