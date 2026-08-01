import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Apis {
  static Options get imTokenOptions =>
      Options(headers: {'token': DataSp.imToken});

  static Options get chatTokenOptions =>
      Options(headers: {'token': DataSp.chatToken});

  static StreamController kickoffController = StreamController<int>.broadcast();

  static void _kickoff(int? errCode) {
    if (errCode == 1501 ||
        errCode == 1503 ||
        errCode == 1504 ||
        errCode == 1505) {
      kickoffController.sink.add(errCode);
    }
  }

  static Future<LoginCertificate> login({
    String? areaCode,
    String? phoneNumber,
    String? account,
    String? email,
    String? password,
    String? verificationCode,
  }) async {
    try {
      var data = await HttpUtil.post(Urls.login, data: {
        "areaCode": areaCode,
        'account': account,
        'phoneNumber': phoneNumber,
        'email': email,
        'password': null != password ? IMUtils.generateMD5(password) : null,
        'platform': IMUtils.getPlatform(),
        'verifyCode': verificationCode,
      });
      final cert = LoginCertificate.fromJson(data!);

      return cert;
    } catch (e, s) {
      _catchErrorHelper(e, s);

      return Future.error(e);
    }
  }

  static Future<LoginCertificate> register({
    required String nickname,
    required String password,
    String? faceURL,
    String? areaCode,
    String? phoneNumber,
    String? email,
    String? account,
    int birth = 0,
    int gender = 1,
    required String verificationCode, // pass '' or demo code when SMS is disabled
    String? invitationCode,
  }) async {
    try {
      var data = await HttpUtil.post(Urls.register, data: {
        'deviceID': DataSp.getDeviceID(),
        'verifyCode': verificationCode.isEmpty ? '666666' : verificationCode,
        'platform': IMUtils.getPlatform(),
        'invitationCode': invitationCode,
        'autoLogin': true,
        'user': {
          "nickname": nickname,
          "faceURL": faceURL,
          'birth': birth,
          'gender': gender,
          'email': email,
          "areaCode": areaCode,
          'phoneNumber': phoneNumber,
          'account': account,
          'password': IMUtils.generateMD5(password),
        },
      });

      final cert = LoginCertificate.fromJson(data!);

      return cert;
    } catch (e, s) {
      _catchErrorHelper(e, s);

      return Future.error(e);
    }
  }

  static Future<dynamic> resetPassword({
    String? areaCode,
    String? phoneNumber,
    String? email,
    required String password,
    required String verificationCode,
  }) async {
    try {
      return HttpUtil.post(
        Urls.resetPwd,
        data: {
          "areaCode": areaCode,
          'phoneNumber': phoneNumber,
          'email': email,
          'password': IMUtils.generateMD5(password),
          'verifyCode': verificationCode,
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
    } catch (e, s) {
      _catchErrorHelper(e, s);
    }
  }

  static Future<bool> changePassword({
    required String userID,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await HttpUtil.post(
        Urls.changePwd,
        data: {
          "userID": userID,
          'currentPassword': IMUtils.generateMD5(currentPassword),
          'newPassword': IMUtils.generateMD5(newPassword),
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
      return true;
    } catch (e, s) {
      _catchErrorHelper(e, s);

      return false;
    }
  }

  static Future<bool> changePasswordOfB({
    required String newPassword,
  }) async {
    try {
      await HttpUtil.post(
        Urls.resetPwd,
        data: {
          'password': IMUtils.generateMD5(newPassword),
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<dynamic> updateUserInfo({
    required String userID,
    String? account,
    String? phoneNumber,
    String? areaCode,
    String? email,
    String? nickname,
    String? faceURL,
    String? signature,
    int? gender,
    int? birth,
    int? level,
    int? allowAddFriend,
    int? allowBeep,
    int? allowVibration,
  }) async {
    try {
      Map<String, dynamic> param = {'userID': userID};
      void put(String key, dynamic value) {
        if (null != value) {
          param[key] = value;
        }
      }

      put('account', account);
      put('phoneNumber', phoneNumber);
      put('areaCode', areaCode);
      put('email', email);
      put('nickname', nickname);
      put('faceURL', faceURL);
      put('signature', signature);
      put('gender', gender);
      put('level', level);
      put('birth', birth);
      put('allowAddFriend', allowAddFriend);
      put('allowBeep', allowBeep);
      put('allowVibration', allowVibration);

      return HttpUtil.post(
        Urls.updateUserInfo,
        data: {
          ...param,
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
    } catch (e, s) {
      _catchErrorHelper(e, s);
    }
  }

  static Future<List<FriendInfo>> searchFriendInfo(
    String keyword, {
    int pageNumber = 1,
    int showNumber = 10,
    bool showErrorToast = true,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.searchFriendInfo,
        data: {
          'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
          'keyword': keyword,
        },
        options: chatTokenOptions,
        showErrorToast: showErrorToast,
      );
      if (data['users'] is List) {
        return (data['users'] as List)
            .map((e) => FriendInfo.fromJson(e))
            .toList();
      }
      return [];
    } catch (e, s) {
      _catchErrorHelper(e, s);

      rethrow;
    }
  }

  static Future<List<UserFullInfo>?> getUserFullInfo({
    int pageNumber = 0,
    int showNumber = 10,
    required List<String> userIDList,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.getUsersFullInfo,
        data: {
          'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
          'userIDs': userIDList,
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
      if (data['users'] is List) {
        return (data['users'] as List)
            .map((e) => UserFullInfo.fromJson(e))
            .toList();
      }
      return null;
    } catch (e, s) {
      _catchErrorHelper(e, s);

      return [];
    }
  }

  static Future<List<UserFullInfo>?> searchUserFullInfo({
    required String content,
    int pageNumber = 1,
    int showNumber = 10,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.searchUserFullInfo,
        data: {
          'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
          'keyword': content,
        },
        options: chatTokenOptions,
      );
      if (data['users'] is List) {
        return (data['users'] as List)
            .map((e) => UserFullInfo.fromJson(e))
            .toList();
      }
      return null;
    } catch (e, s) {
      _catchErrorHelper(e, s);

      return [];
    }
  }

  static Future<UserFullInfo?> queryMyFullInfo() async {
    final list = await Apis.getUserFullInfo(
      userIDList: [OpenIM.iMManager.userID],
    );
    return list?.firstOrNull;
  }

  static Future<bool> requestVerificationCode({
    String? areaCode,
    String? phoneNumber,
    String? email,
    required int usedFor,
    String? invitationCode,
  }) async {
    return HttpUtil.post(
      Urls.getVerificationCode,
      data: {
        "areaCode": areaCode,
        "phoneNumber": phoneNumber,
        "email": email,
        'usedFor': usedFor,
        'invitationCode': invitationCode
      },
    ).then((value) {
      IMViews.showToast(StrRes.sentSuccessfully);
      return true;
    }).catchError((e, s) {
      _catchErrorHelper(e, s);

      return false;
    });
  }

  static Future<SignalingCertificate> getTokenForRTC(
      String roomID, String userID) async {
    return HttpUtil.post(
      Urls.getTokenForRTC,
      data: {
        "room": roomID,
        "identity": userID,
      },
      options: chatTokenOptions,
    ).then((value) {
      final signaling = SignalingCertificate.fromJson(value)..roomID = roomID;
      return signaling;
    }).catchError((e, s) {
      _catchErrorHelper(e, s);

      throw e;
    });
  }

  static Future<dynamic> checkVerificationCode({
    String? areaCode,
    String? phoneNumber,
    String? email,
    required String verificationCode,
    required int usedFor,
    String? invitationCode,
  }) {
    return HttpUtil.post(
      Urls.checkVerificationCode,
      data: {
        "phoneNumber": phoneNumber,
        "areaCode": areaCode,
        "email": email,
        "verifyCode": verificationCode,
        "usedFor": usedFor,
        'invitationCode': invitationCode
      },
    );
  }

  static Future<UpgradeInfoV2> checkUpgradeV2() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final data = await HttpUtil.post(
      Urls.upgrade,
      data: {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'version': packageInfo.version,
      },
      showErrorToast: false,
    );
    if (data is Map) {
      return UpgradeInfoV2.fromApplicationVersion(
        Map<String, dynamic>.from(data),
      );
    }
    return Future.error(data);
  }

  static Future<Map<String, dynamic>> getClientConfig() async {
    final defaultConfig = {
      'discoverPageURL': Config.discoverPageURL,
      'allowSendMsgNotFriend': Config.allowSendMsgNotFriend,
    };
    try {
      final data = await HttpUtil.post(
        Urls.getClientConfig,
        showErrorToast: false,
      );
      if (data is Map && data['config'] is Map) {
        return {
          ...defaultConfig,
          ...Map<String, dynamic>.from(data['config']),
        };
      }
      if (data is Map) {
        return {
          ...defaultConfig,
          ...Map<String, dynamic>.from(data),
        };
      }
    } catch (e, s) {
      Logger.print('getClientConfig fallback: e:$e s:$s');
    }
    return defaultConfig;
  }

  /// Queries the read/unread member userIDs of one group message.
  /// [filter] 0 = read members, 1 = unread members.
  /// Returns null on failure so callers can show an error state.
  static Future<GroupMessageReaderListResult?> getGroupMessageReaderList({
    required String conversationID,
    required String clientMsgID,
    required int seq,
    required int filter,
    int offset = 0,
    int count = 500,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.getGroupMessageReaderList,
        data: {
          'conversationID': conversationID,
          'clientMsgID': clientMsgID,
          'seq': seq,
          'filter': filter,
          'offset': offset,
          'count': count,
        },
        options: imTokenOptions,
        showErrorToast: false,
      );
      return GroupMessageReaderListResult.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : {});
    } catch (e, s) {
      Logger.print('getGroupMessageReaderList error: e:$e s:$s');
      return null;
    }
  }

  /// Batch queries read counts for group messages, used to backfill the
  /// "N read / N unread" tag when opening a chat.
  /// Returns null on failure.
  static Future<List<GroupMessageReadInfoResult>?> getGroupMessagesReadInfo({
    required String conversationID,
    required List<({String clientMsgID, int seq})> items,
  }) async {
    if (items.isEmpty) return [];
    try {
      final data = await HttpUtil.post(
        Urls.getGroupMessagesReadInfo,
        data: {
          'conversationID': conversationID,
          'items': items
              .map((e) => {'clientMsgID': e.clientMsgID, 'seq': e.seq})
              .toList(),
        },
        options: imTokenOptions,
        showErrorToast: false,
      );
      final list = data is Map ? data['readInfos'] : null;
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => GroupMessageReadInfoResult.fromJson(
                Map<String, dynamic>.from(e)))
            .toList();
      }
      return [];
    } catch (e, s) {
      Logger.print('getGroupMessagesReadInfo error: e:$e s:$s');
      return null;
    }
  }

  static Future<List<OnlineStatus>> getUsersOnlineStatus({
    required List<String> userIDList,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.onlineStatus,
        data: {'userIDs': userIDList},
        options: imTokenOptions,
        showErrorToast: false,
      );
      if (data is List) {
        return data.map((e) => OnlineStatus.fromJson(e)).toList();
      }
      return [];
    } catch (e, s) {
      Logger.print('getUsersOnlineStatus error: e:$e s:$s');
      return [];
    }
  }

  static Future<MomentFeedResp> getMomentsFeed({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final data = await HttpUtil.get(
        Urls.momentsFeed,
        queryParameters: {
          if (cursor != null) 'cursor': cursor,
          'limit': limit,
        },
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentFeedResp.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('getMomentsFeed error: e:$e s:$s');
    }
    return MomentFeedResp(list: [], hasMore: false);
  }

  static Future<MomentProfile> getMomentProfile(String userID) async {
    try {
      final data = await HttpUtil.get(
        Urls.momentProfile(userID),
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentProfile.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('getMomentProfile error: e:$e s:$s');
    }
    return MomentProfile(userID: userID);
  }

  static Future<MomentProfile> updateMomentCover(String coverUrl) async {
    try {
      final data = await HttpUtil.put(
        Urls.momentCover,
        data: {'coverUrl': coverUrl},
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentProfile.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('updateMomentCover error: e:$e s:$s');
    }
    IMViews.showToast(StrRes.networkError);
    return Future.error('moments profile unavailable');
  }

  static Future<MomentPost> createMomentPost({
    required String content,
    required String mediaType,
    required List<MomentMedia> mediaList,
    String visibility = MomentVisibility.friends,
    List<String>? allowUserIDs,
    List<String>? excludeUserIDs,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.momentPosts,
        data: {
          'content': content,
          'mediaType': mediaType,
          'mediaList': mediaList.map((e) => e.toJson()).toList(),
          'visibility': visibility,
          if (allowUserIDs != null) 'allowUserIDs': allowUserIDs,
          if (excludeUserIDs != null) 'excludeUserIDs': excludeUserIDs,
        },
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentPost.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('createMomentPost error: e:$e s:$s');
    }
    IMViews.showToast(StrRes.networkError);
    return Future.error('moments unavailable');
  }

  static Future<void> deleteMomentPost(String postID) async {
    try {
      await HttpUtil.delete(
        Urls.momentPost(postID),
        options: chatTokenOptions,
        showErrorToast: false,
      );
    } catch (e, s) {
      Logger.print('deleteMomentPost error: e:$e s:$s');
      IMViews.showToast(StrRes.networkError);
      rethrow;
    }
  }

  static Future<MomentPost> likeMomentPost(String postID) async {
    try {
      final data = await HttpUtil.post(
        Urls.momentLikes(postID),
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentPost.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('likeMomentPost error: e:$e s:$s');
      IMViews.showToast(StrRes.networkError);
    }
    return Future.error('moments unavailable');
  }

  static Future<MomentPost> unlikeMomentPost(String postID) async {
    try {
      final data = await HttpUtil.delete(
        Urls.momentLikes(postID),
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentPost.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('unlikeMomentPost error: e:$e s:$s');
      IMViews.showToast(StrRes.networkError);
    }
    return Future.error('moments unavailable');
  }

  static Future<MomentComment> createMomentComment({
    required String postID,
    required String content,
    String? replyToUserID,
    String? replyToNickname,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.momentComments(postID),
        data: {
          'content': content,
          if (replyToUserID != null) 'replyToUserID': replyToUserID,
          if (replyToNickname != null) 'replyToNickname': replyToNickname,
        },
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentComment.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('createMomentComment error: e:$e s:$s');
      IMViews.showToast(StrRes.networkError);
    }
    return Future.error('moments unavailable');
  }

  static Future<void> deleteMomentComment(String commentID) async {
    try {
      await HttpUtil.delete(
        Urls.momentComment(commentID),
        options: chatTokenOptions,
        showErrorToast: false,
      );
    } catch (e, s) {
      Logger.print('deleteMomentComment error: e:$e s:$s');
      IMViews.showToast(StrRes.networkError);
      rethrow;
    }
  }

  static Future<MomentNotificationResp> getMomentNotifications({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final data = await HttpUtil.get(
        Urls.momentNotifications,
        queryParameters: {
          if (cursor != null) 'cursor': cursor,
          'limit': limit,
        },
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return MomentNotificationResp.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('getMomentNotifications error: e:$e s:$s');
    }
    return MomentNotificationResp(list: [], hasMore: false);
  }

  static Future<void> markMomentNotificationsRead() async {
    try {
      await HttpUtil.post(
        Urls.markMomentNotificationsRead,
        options: chatTokenOptions,
        showErrorToast: false,
      );
    } catch (e, s) {
      Logger.print('markMomentNotificationsRead error: e:$e s:$s');
    }
  }

  static Future<ConversationCategoryConfig>
      getConversationCategoryConfig() async {
    try {
      final data = await HttpUtil.get(
        Urls.conversationCategoryConfig,
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return ConversationCategoryConfig.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
    } catch (e, s) {
      Logger.print('getConversationCategoryConfig error: e:$e s:$s');
    }
    return ConversationCategoryConfig();
  }

  static Future<ConversationCategoryConfig> updateConversationCategoryConfig({
    required bool folderTabsEnabled,
    required List<String> enabledAutoCategories,
    required List<ConversationTag> customTags,
  }) async {
    try {
      final data = await HttpUtil.put(
        Urls.conversationCategoryConfig,
        data: {
          'folderTabsEnabled': folderTabsEnabled,
          'enabledAutoCategories': enabledAutoCategories,
          'customTags': customTags.map((e) => e.toJson()).toList(),
        },
        options: chatTokenOptions,
      );
      return ConversationCategoryConfig.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e, s) {
      _catchErrorHelper(e, s);
      rethrow;
    }
  }

  static Future<ConversationCategoryConfig> createConversationTag({
    required String name,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.conversationCategoryTags,
        data: {'name': name},
        options: chatTokenOptions,
      );
      return ConversationCategoryConfig.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e, s) {
      _catchErrorHelper(e, s);
      rethrow;
    }
  }

  static Future<ConversationCategoryConfig> renameConversationTag({
    required String tagID,
    required String name,
  }) async {
    try {
      final data = await HttpUtil.put(
        Urls.conversationCategoryTag(tagID),
        data: {'name': name},
        options: chatTokenOptions,
      );
      return ConversationCategoryConfig.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e, s) {
      _catchErrorHelper(e, s);
      rethrow;
    }
  }

  static Future<ConversationCategoryConfig> deleteConversationTag({
    required String tagID,
  }) async {
    try {
      final data = await HttpUtil.delete(
        Urls.conversationCategoryTag(tagID),
        options: chatTokenOptions,
      );
      return ConversationCategoryConfig.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e, s) {
      _catchErrorHelper(e, s);
      rethrow;
    }
  }

  static Future<ConversationCategoryConfig> setConversationTags({
    required String conversationID,
    required List<String> tagIDs,
  }) async {
    try {
      final data = await HttpUtil.put(
        Urls.conversationCategoryConversationTags(conversationID),
        data: {'tagIDs': tagIDs},
        options: chatTokenOptions,
      );
      return ConversationCategoryConfig.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e, s) {
      _catchErrorHelper(e, s);
      rethrow;
    }
  }

  static Future<List<UniMPInfo>> findApplets() async {
    try {
      final data = await HttpUtil.post(
        Urls.findApplet,
        data: {},
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map && data['applets'] is List) {
        final list = (data['applets'] as List)
            .whereType<Map>()
            .map((e) => UniMPInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        list.sort((a, b) => (b.priority ?? 0).compareTo(a.priority ?? 0));
        return list;
      }
      return [];
    } catch (e, s) {
      Logger.print('findApplets error: e:$e s:$s');
      return [];
    }
  }

  static Future<AgentPageResp> pageFindAgents({
    int pageNumber = 1,
    int showNumber = 20,
    List<String>? userIDs,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.agentPage,
        data: {
          'pagination': {
            'pageNumber': pageNumber,
            'showNumber': showNumber,
          },
          if (userIDs != null) 'userIDs': userIDs,
        },
        options: chatTokenOptions,
        showErrorToast: false,
      );
      if (data is Map) {
        return AgentPageResp.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e, s) {
      Logger.print('pageFindAgents error: e:$e s:$s');
    }
    return AgentPageResp(total: 0, agents: []);
  }

  static void _catchErrorHelper(Object e, StackTrace s) {
    if (e is (int, String?)) {
      final errCode = e.$1;
      final errMsg = e.$2;
      _kickoff(errCode);

      Logger.print('e:$errCode s:$errMsg');
    } else {
      _catchError(e, s);
    }
  }

  static void _catchError(Object e, StackTrace s, {bool forceBack = true}) {
    Logger.print('_catchError: $e $s');
    final route = Get.currentRoute;
    if (route == '/login' || route == '/splash') {
      return;
    }
    IMViews.showToast(StrRes.networkError);

    if (forceBack) {
      DataSp.removeLoginCertificate();
      Get.offAllNamed('/login');
    }
  }
}

class GroupMessageReaderListResult {
  final List<String> userIDs;
  final int total;
  final int hasReadCount;
  final int unreadCount;

  GroupMessageReaderListResult({
    required this.userIDs,
    required this.total,
    required this.hasReadCount,
    required this.unreadCount,
  });

  factory GroupMessageReaderListResult.fromJson(Map<String, dynamic> json) =>
      GroupMessageReaderListResult(
        userIDs: ((json['userIDs'] ?? []) as List)
            .map((e) => e.toString())
            .toList(),
        total: json['total'] ?? 0,
        hasReadCount: json['hasReadCount'] ?? 0,
        unreadCount: json['unreadCount'] ?? 0,
      );
}

class GroupMessageReadInfoResult {
  final String clientMsgID;
  final int seq;
  final int hasReadCount;
  final int unreadCount;
  final int groupMemberCount;

  GroupMessageReadInfoResult({
    required this.clientMsgID,
    required this.seq,
    required this.hasReadCount,
    required this.unreadCount,
    required this.groupMemberCount,
  });

  factory GroupMessageReadInfoResult.fromJson(Map<String, dynamic> json) =>
      GroupMessageReadInfoResult(
        clientMsgID: json['clientMsgID'] ?? '',
        seq: json['seq'] ?? 0,
        hasReadCount: json['hasReadCount'] ?? 0,
        unreadCount: json['unreadCount'] ?? 0,
        groupMemberCount: json['groupMemberCount'] ?? 0,
      );
}
