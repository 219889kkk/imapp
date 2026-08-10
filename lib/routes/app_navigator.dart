import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../pages/chat/group_setup/edit_name/edit_name_logic.dart';
import '../pages/chat/group_setup/group_member_list/group_member_list_logic.dart';
import '../pages/contacts/add_by_search/add_by_search_logic.dart';
import '../pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import '../pages/contacts/select_contacts/select_contacts_logic.dart';
import '../pages/mine/edit_my_info/edit_my_info_logic.dart';
import 'app_pages.dart';

class AppNavigator {
  AppNavigator._();

  static void startLogin() {
    Get.offAllNamed(AppRoutes.login);
  }

  static void startBackLogin() {
    Get.until((route) => Get.currentRoute == AppRoutes.login);
  }

  static void startMain(
      {bool isAutoLogin = false, List<ConversationInfo>? conversations}) {
    Get.offAllNamed(
      AppRoutes.home,
      arguments: {'isAutoLogin': isAutoLogin, 'conversations': conversations},
    );
  }

  static void startSplashToMain(
      {bool isAutoLogin = false, List<ConversationInfo>? conversations}) {
    Get.offAndToNamed(
      AppRoutes.home,
      arguments: {'isAutoLogin': isAutoLogin, 'conversations': conversations},
    );
  }

  static void startBackMain() {
    Get.until((route) => Get.currentRoute == AppRoutes.home);
  }

  static startMoments() => Get.toNamed(AppRoutes.moments);

  static Future<dynamic>? startMomentsPublish() =>
      Get.toNamed(AppRoutes.momentsPublish);

  static startMomentsNotifications() =>
      Get.toNamed(AppRoutes.momentsNotifications);

  static startWorkbench() => Get.toNamed(AppRoutes.workbench);

  static startH5({required String url, String? title}) => Get.to(
        () => H5Container(url: url, title: title),
      );

  static Future<T?>? startChat<T>({
    required ConversationInfo conversationInfo,
    bool offUntilHome = true,
    String? draftText,
    Message? searchMessage,
    List<Message>? prefetchedMessages,
    bool prefetchedMessagesIsEnd = false,
  }) async {
    GetTags.createChatTag();

    final arguments = {
      'draftText': draftText,
      'conversationInfo': conversationInfo,
      'searchMessage': searchMessage,
      'prefetchedMessages': prefetchedMessages,
      'prefetchedMessagesIsEnd': prefetchedMessagesIsEnd,
    };

    return offUntilHome
        ? Get.offNamedUntil(
            AppRoutes.chat,
            (route) => route.settings.name == AppRoutes.home,
            arguments: arguments,
          )
        : Get.toNamed(
            AppRoutes.chat,
            arguments: arguments,
            preventDuplicates: false,
          );
  }

  static startAddContactsMethod() => Get.toNamed(AppRoutes.addContactsMethod);

  static startAddContactsBySearch({required SearchType searchType}) =>
      Get.toNamed(
        AppRoutes.addContactsBySearch,
        arguments: {"searchType": searchType},
      );

  static startUserProfilePane({
    required String userID,
    String? groupID,
    String? nickname,
    String? faceURL,
    bool offAllWhenDelFriend = false,
    bool offAndToNamed = false,
    bool forceCanAdd = false,
  }) {
    GetTags.createUserProfileTag();

    final arguments = {
      'groupID': groupID,
      'userID': userID,
      'nickname': nickname,
      'faceURL': faceURL,
      'offAllWhenDelFriend': offAllWhenDelFriend,
      'forceCanAdd': forceCanAdd,
    };

    return offAndToNamed
        ? Get.offAndToNamed(AppRoutes.userProfilePanel, arguments: arguments)
        : Get.toNamed(
            AppRoutes.userProfilePanel,
            arguments: arguments,
            preventDuplicates: false,
          );
  }

  static startPersonalInfo({
    required String userID,
  }) =>
      Get.toNamed(AppRoutes.personalInfo, arguments: {
        'userID': userID,
      });

  static startFriendSetup({
    required String userID,
  }) =>
      Get.toNamed(AppRoutes.friendSetup, arguments: {
        'userID': userID,
      });

  static startSetFriendRemark() =>
      Get.toNamed(AppRoutes.setFriendRemark, arguments: {});

  static startSendVerificationApplication({
    String? userID,
    String? groupID,
    JoinGroupMethod? joinGroupMethod,
  }) =>
      Get.toNamed(AppRoutes.sendVerificationApplication, arguments: {
        'joinGroupMethod': joinGroupMethod,
        'userID': userID,
        'groupID': groupID,
      });

  static startGroupProfilePanel({
    required String groupID,
    required JoinGroupMethod joinGroupMethod,
    bool offAndToNamed = false,
  }) =>
      offAndToNamed
          ? Get.offAndToNamed(AppRoutes.groupProfilePanel, arguments: {
              'joinGroupMethod': joinGroupMethod,
              'groupID': groupID,
            })
          : Get.toNamed(AppRoutes.groupProfilePanel, arguments: {
              'joinGroupMethod': joinGroupMethod,
              'groupID': groupID,
            });

  static startMyInfo() => Get.toNamed(AppRoutes.myInfo);

  static startEditMyInfo({EditAttr attr = EditAttr.nickname, int? maxLength}) =>
      Get.toNamed(AppRoutes.editMyInfo,
          arguments: {'editAttr': attr, 'maxLength': maxLength});

  static Future<dynamic>? startMyQrcode() => Get.toNamed(AppRoutes.myQrcode);

  static startAccountSetup() => Get.toNamed(AppRoutes.accountSetup);

  static startChatNotificationSetup() =>
      Get.toNamed(AppRoutes.chatNotificationSetup);

  static startPrivacySecuritySetup() =>
      Get.toNamed(AppRoutes.privacySecuritySetup);

  static startAppearanceLanguageSetup() =>
      Get.toNamed(AppRoutes.appearanceLanguageSetup);

  static Future<dynamic>? startChangePassword() =>
      Get.toNamed(AppRoutes.changePassword);

  static startBlacklist() => Get.toNamed(AppRoutes.blacklist);

  static startLanguageSetup() => Get.toNamed(AppRoutes.languageSetup);

  static Future<dynamic>? startThemeSetup() =>
      Get.toNamed(AppRoutes.themeSetup);

  static startAboutUs() => Get.toNamed(AppRoutes.aboutUs);

  static startCallAudioDebug() => Get.toNamed(AppRoutes.callAudioDebug);

  static startChatSetup({
    required ConversationInfo conversationInfo,
  }) =>
      Get.toNamed(AppRoutes.chatSetup, arguments: {
        'conversationInfo': conversationInfo,
      });

  static startChatReadDetail({
    required Message message,
    required String conversationID,
  }) =>
      Get.toNamed(AppRoutes.chatReadDetail, arguments: {
        'message': message,
        'conversationID': conversationID,
      });

  static startMergeMessageDetail({
    required String title,
    required List<Message> messages,
  }) =>
      Get.toNamed(AppRoutes.mergeMessageDetail, arguments: {
        'title': title,
        'messages': messages,
      });

  static startGroupAnnouncementDetail({
    required String content,
    int? updateTime,
  }) =>
      Get.toNamed(AppRoutes.groupAnnouncementDetail, arguments: {
        'content': content,
        'updateTime': updateTime ?? 0,
      });

  static startGroupChatSetup({
    required ConversationInfo conversationInfo,
  }) =>
      Get.toNamed(AppRoutes.groupChatSetup, arguments: {
        'conversationInfo': conversationInfo,
      });

  static startGroupManage({
    required GroupInfo groupInfo,
  }) =>
      Get.toNamed(AppRoutes.groupManage, arguments: {
        'groupInfo': groupInfo,
      });

  static startEditGroupName({required EditNameType type, String? faceUrl}) =>
      Get.toNamed(AppRoutes.editGroupName, arguments: {
        'type': type,
        'faceUrl': faceUrl,
      });

  static Future<T?>? startGroupMemberList<T>({
    required GroupInfo groupInfo,
    GroupMemberOpType opType = GroupMemberOpType.view,
  }) =>
      Get.toNamed(AppRoutes.groupMemberList,
          preventDuplicates: false,
          arguments: {
            'groupInfo': groupInfo,
            'opType': opType,
          });

  static startSearchGroupMember({
    required GroupInfo groupInfo,
    GroupMemberOpType opType = GroupMemberOpType.view,
  }) =>
      Get.toNamed(AppRoutes.searchGroupMember, arguments: {
        'groupInfo': groupInfo,
        'opType': opType,
      });

  static startGroupQrcode() => Get.toNamed(AppRoutes.groupQrcode);

  static startFriendRequests() => Get.toNamed(AppRoutes.friendRequests);

  static startProcessFriendRequests({
    required FriendApplicationInfo applicationInfo,
  }) =>
      Get.toNamed(AppRoutes.processFriendRequests, arguments: {
        'applicationInfo': applicationInfo,
      });

  static startGroupRequests() => Get.toNamed(AppRoutes.groupRequests);

  static startProcessGroupRequests({
    required GroupApplicationInfo applicationInfo,
  }) =>
      Get.toNamed(AppRoutes.processGroupRequests, arguments: {
        'applicationInfo': applicationInfo,
      });

  static startFriendList() => Get.toNamed(AppRoutes.friendList);

  static startGroupList() => Get.toNamed(AppRoutes.groupList);

  static Future<dynamic>? startScan() => Get.toNamed(AppRoutes.scan);

  static startSelectContacts({
    required SelAction action,
    List<String>? defaultCheckedIDList,
    List<dynamic>? checkedList,
    List<String>? excludeIDList,
    bool openSelectedSheet = false,
    String? groupID,
    String? ex,
  }) =>
      Get.toNamed(AppRoutes.selectContacts, arguments: {
        'action': action,
        'defaultCheckedIDList': defaultCheckedIDList,
        'checkedList': IMUtils.convertCheckedListToMap(checkedList),
        'excludeIDList': excludeIDList,
        'openSelectedSheet': openSelectedSheet,
        'groupID': groupID,
        'ex': ex,
      });

  static startSelectContactsFromFriends() =>
      Get.toNamed(AppRoutes.selectContactsFromFriends);

  static startSelectContactsFromGroup() =>
      Get.toNamed(AppRoutes.selectContactsFromGroup);

  static startSelectContactsFromSearch() =>
      Get.toNamed(AppRoutes.selectContactsFromSearch);

  static startCreateGroup({
    List<UserInfo> defaultCheckedList = const [],
  }) async {
    final result = await startSelectContacts(
      action: SelAction.crateGroup,
      defaultCheckedIDList: defaultCheckedList.map((e) => e.userID!).toList(),
    );
    final list = IMUtils.convertSelectContactsResultToUserInfo(result);
    if (list is List<UserInfo>) {
      return Get.toNamed(
        AppRoutes.createGroup,
        arguments: {
          'checkedList': list,
          'defaultCheckedList': defaultCheckedList
        },
      );
    }
    return null;
  }

  static startGlobalSearch() => Get.toNamed(AppRoutes.globalSearch);

  static startExpandChatHistory({
    required SearchResultItems searchResultItems,
    required String defaultSearchKey,
  }) =>
      Get.toNamed(AppRoutes.expandChatHistory, arguments: {
        'searchResultItems': searchResultItems,
        'defaultSearchKey': defaultSearchKey,
      });

  static startRegister() => Get.toNamed(AppRoutes.register);

  static void startVerifyPhone({
    String? phoneNumber,
    String? email,
    required String areaCode,
    required int usedFor,
    String? invitationCode,
  }) =>
      Get.toNamed(AppRoutes.verifyPhone, arguments: {
        'phoneNumber': phoneNumber,
        'email': email,
        'areaCode': areaCode,
        'usedFor': usedFor,
        'invitationCode': invitationCode,
      });

  static void startSetPassword({
    String? phoneNumber,
    String? email,
    required String areaCode,
    required int usedFor,
    required String verificationCode,
    String? invitationCode,
  }) =>
      Get.toNamed(AppRoutes.setPassword, arguments: {
        'phoneNumber': phoneNumber,
        'email': email,
        'areaCode': areaCode,
        'usedFor': usedFor,
        'verificationCode': verificationCode,
        'invitationCode': invitationCode
      });

  static void startSetSelfInfo({
    String? phoneNumber,
    String? email,
    String? account,
    required String areaCode,
    required password,
    required int usedFor,
    required String verificationCode,
    String? invitationCode,
  }) =>
      Get.toNamed(AppRoutes.setSelfInfo, arguments: {
        'phoneNumber': phoneNumber,
        'email': email,
        'account': account,
        'areaCode': areaCode,
        'password': password,
        'usedFor': usedFor,
        'verificationCode': verificationCode,
        'invitationCode': invitationCode
      });

  static startForgetPassword() => Get.toNamed(AppRoutes.forgetPassword);

  static void startResetPassword({
    String? phoneNumber,
    String? email,
    String? account,
    required String areaCode,
    required String verificationCode,
  }) =>
      Get.toNamed(AppRoutes.resetPassword, arguments: {
        'phoneNumber': phoneNumber,
        'email': email,
        'account': account,
        'areaCode': areaCode,
        'usedFor': 2,
        'verificationCode': verificationCode,
      });

  static startSelectContactsFromTag() =>
      Get.toNamed(AppRoutes.selectContactsFromTag);
}
