import 'config.dart';

/// All URLs are getters so host failover updates take effect immediately.
class Urls {
  static String get onlineStatus =>
      "${Config.imApiUrl}/user/get_users_online_status";
  static String get queryAllUsers =>
      "${Config.imApiUrl}/manager/get_all_users_uid";
  static String get getGroupMessageReaderList =>
      "${Config.imApiUrl}/msg/get_group_message_reader_list";
  static String get getGroupMessagesReadInfo =>
      "${Config.imApiUrl}/msg/get_group_messages_read_info";
  static String get updateUserInfo => "${Config.appAuthUrl}/user/update";
  static String get searchFriendInfo => "${Config.appAuthUrl}/friend/search";
  static String get getUsersFullInfo => "${Config.appAuthUrl}/user/find/full";
  static String get searchUserFullInfo =>
      "${Config.appAuthUrl}/user/search/full";

  static String get getVerificationCode =>
      "${Config.appAuthUrl}/account/code/send";
  static String get checkVerificationCode =>
      "${Config.appAuthUrl}/account/code/verify";
  static String get register => "${Config.appAuthUrl}/account/register";

  static String get resetPwd => "${Config.appAuthUrl}/account/password/reset";
  static String get changePwd => "${Config.appAuthUrl}/account/password/change";
  static String get login => "${Config.appAuthUrl}/account/login";

  static String get upgrade => "${Config.appAuthUrl}/application/latest_version";
  static String get getClientConfig => '${Config.appAuthUrl}/client_config/get';
  static String get getTokenForRTC =>
      "${Config.appAuthUrl}/user/rtc/get_token";

  /// Trigger APNs VoIP / CallKit push for a call invite (see docs/VOIP_CALLKIT.md).
  static String get voipPush => "${Config.appAuthUrl}/user/rtc/voip_push";

  /// Callee reports PushKit VoIP device token (stored per userID for direct APNs).
  static String get voipToken => "${Config.appAuthUrl}/user/rtc/voip_token";
  static String get voipTokenDelete =>
      "${Config.appAuthUrl}/user/rtc/voip_token/delete";

  static String get momentsFeed => "${Config.appAuthUrl}/moments/feed";
  static String get momentPosts => "${Config.appAuthUrl}/moments/posts";
  static String momentProfile(String userID) =>
      "${Config.appAuthUrl}/moments/profile/$userID";
  static String get momentCover =>
      "${Config.appAuthUrl}/moments/profile/cover";
  static String momentPost(String postID) =>
      "${Config.appAuthUrl}/moments/posts/$postID";
  static String momentLikes(String postID) =>
      "${Config.appAuthUrl}/moments/posts/$postID/likes";
  static String momentComments(String postID) =>
      "${Config.appAuthUrl}/moments/posts/$postID/comments";
  static String momentComment(String commentID) =>
      "${Config.appAuthUrl}/moments/comments/$commentID";
  static String get momentNotifications =>
      "${Config.appAuthUrl}/moments/notifications";
  static String get markMomentNotificationsRead =>
      "${Config.appAuthUrl}/moments/notifications/read";

  static String get conversationCategoryConfig =>
      "${Config.appAuthUrl}/conversation_categories/config";
  static String get conversationCategoryTags =>
      "${Config.appAuthUrl}/conversation_categories/tags";
  static String conversationCategoryTag(String tagID) =>
      "${Config.appAuthUrl}/conversation_categories/tags/$tagID";
  static String conversationCategoryConversationTags(String conversationID) =>
      "${Config.appAuthUrl}/conversation_categories/conversations/$conversationID/tags";

  static String get findApplet => "${Config.appAuthUrl}/applet/find";
  static String get agentPage => "${Config.botApiUrl}/agent/page";
}
