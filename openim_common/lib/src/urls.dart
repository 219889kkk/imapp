import 'config.dart';

class Urls {
  static final onlineStatus = "${Config.imApiUrl}/user/get_users_online_status";
  static final queryAllUsers = "${Config.imApiUrl}/manager/get_all_users_uid";
  static final getGroupMessageReaderList =
      "${Config.imApiUrl}/msg/get_group_message_reader_list";
  static final getGroupMessagesReadInfo =
      "${Config.imApiUrl}/msg/get_group_messages_read_info";
  static final updateUserInfo = "${Config.appAuthUrl}/user/update";
  static final searchFriendInfo = "${Config.appAuthUrl}/friend/search";
  static final getUsersFullInfo = "${Config.appAuthUrl}/user/find/full";
  static final searchUserFullInfo = "${Config.appAuthUrl}/user/search/full";

  static final getVerificationCode = "${Config.appAuthUrl}/account/code/send";
  static final checkVerificationCode =
      "${Config.appAuthUrl}/account/code/verify";
  static final register = "${Config.appAuthUrl}/account/register";

  static final resetPwd = "${Config.appAuthUrl}/account/password/reset";
  static final changePwd = "${Config.appAuthUrl}/account/password/change";
  static final login = "${Config.appAuthUrl}/account/login";

  static final upgrade = "${Config.appAuthUrl}/application/latest_version";
  static final getClientConfig = '${Config.appAuthUrl}/client_config/get';
  static final getTokenForRTC = "${Config.appAuthUrl}/user/rtc/get_token";

  static final momentsFeed = "${Config.appAuthUrl}/moments/feed";
  static final momentPosts = "${Config.appAuthUrl}/moments/posts";
  static String momentProfile(String userID) =>
      "${Config.appAuthUrl}/moments/profile/$userID";
  static final momentCover = "${Config.appAuthUrl}/moments/profile/cover";
  static String momentPost(String postID) =>
      "${Config.appAuthUrl}/moments/posts/$postID";
  static String momentLikes(String postID) =>
      "${Config.appAuthUrl}/moments/posts/$postID/likes";
  static String momentComments(String postID) =>
      "${Config.appAuthUrl}/moments/posts/$postID/comments";
  static String momentComment(String commentID) =>
      "${Config.appAuthUrl}/moments/comments/$commentID";
  static final momentNotifications =
      "${Config.appAuthUrl}/moments/notifications";
  static final markMomentNotificationsRead =
      "${Config.appAuthUrl}/moments/notifications/read";

  static final conversationCategoryConfig =
      "${Config.appAuthUrl}/conversation_categories/config";
  static final conversationCategoryTags =
      "${Config.appAuthUrl}/conversation_categories/tags";
  static String conversationCategoryTag(String tagID) =>
      "${Config.appAuthUrl}/conversation_categories/tags/$tagID";
  static String conversationCategoryConversationTags(String conversationID) =>
      "${Config.appAuthUrl}/conversation_categories/conversations/$conversationID/tags";

  static final findApplet = "${Config.appAuthUrl}/applet/find";
  static final agentPage = "${Config.botApiUrl}/agent/page";
}
