import 'package:get/get.dart';

import '../pages/chat/chat_binding.dart';
import '../pages/chat/chat_read_detail/chat_read_detail_binding.dart';
import '../pages/chat/chat_read_detail/chat_read_detail_view.dart';
import '../pages/chat/merge_message_detail/merge_message_detail_binding.dart';
import '../pages/chat/merge_message_detail/merge_message_detail_view.dart';
import '../pages/chat/group_announcement_detail/group_announcement_detail_binding.dart';
import '../pages/chat/group_announcement_detail/group_announcement_detail_view.dart';
import '../pages/chat/chat_setup/chat_setup_binding.dart';
import '../pages/chat/chat_setup/chat_setup_view.dart';
import '../pages/chat/chat_view.dart';
import '../pages/chat/group_setup/edit_name/edit_name_binding.dart';
import '../pages/chat/group_setup/edit_name/edit_name_view.dart';
import '../pages/chat/group_setup/group_manage/group_manage_binding.dart';
import '../pages/chat/group_setup/group_manage/group_manage_view.dart';
import '../pages/chat/group_setup/group_member_list/group_member_list_binding.dart';
import '../pages/chat/group_setup/group_member_list/group_member_list_view.dart';
import '../pages/chat/group_setup/group_qrcode/group_qrcode_binding.dart';
import '../pages/chat/group_setup/group_qrcode/group_qrcode_view.dart';
import '../pages/chat/group_setup/search_group_member/search_group_member_binding.dart';
import '../pages/chat/group_setup/search_group_member/search_group_member_view.dart';
import '../pages/chat/group_setup/group_setup_binding.dart';
import '../pages/chat/group_setup/group_setup_view.dart';
import '../pages/contacts/add_by_search/add_by_search_binding.dart';
import '../pages/contacts/add_by_search/add_by_search_view.dart';
import '../pages/contacts/add_method/add_method_binding.dart';
import '../pages/contacts/add_method/add_method_view.dart';
import '../pages/contacts/create_group/create_group_binding.dart';
import '../pages/contacts/create_group/create_group_view.dart';
import '../pages/contacts/scan/scan_binding.dart';
import '../pages/contacts/scan/scan_view.dart';
import '../pages/contacts/friend_list/friend_list_binding.dart';
import '../pages/contacts/friend_list/friend_list_view.dart';
import '../pages/contacts/friend_requests/friend_requests_binding.dart';
import '../pages/contacts/friend_requests/friend_requests_view.dart';
import '../pages/contacts/friend_requests/process_friend_requests/process_friend_requests_binding.dart';
import '../pages/contacts/friend_requests/process_friend_requests/process_friend_requests_view.dart';
import '../pages/contacts/group_list/group_list_binding.dart';
import '../pages/contacts/group_list/group_list_view.dart';
import '../pages/contacts/group_profile_panel/group_profile_panel_binding.dart';
import '../pages/contacts/group_profile_panel/group_profile_panel_view.dart';
import '../pages/contacts/group_requests/group_requests_binding.dart';
import '../pages/contacts/group_requests/group_requests_view.dart';
import '../pages/contacts/group_requests/process_group_requests/process_group_requests_binding.dart';
import '../pages/contacts/group_requests/process_group_requests/process_group_requests_view.dart';
import '../pages/contacts/select_contacts/friend_list/friend_list_binding.dart';
import '../pages/contacts/select_contacts/friend_list/friend_list_view.dart';
import '../pages/contacts/select_contacts/group_list/group_list_binding.dart';
import '../pages/contacts/select_contacts/group_list/group_list_view.dart';
import '../pages/contacts/select_contacts/search_contacts/search_contacts_binding.dart';
import '../pages/contacts/select_contacts/search_contacts/search_contacts_view.dart';
import '../pages/contacts/select_contacts/select_contacts_binding.dart';
import '../pages/contacts/select_contacts/select_contacts_view.dart';
import '../pages/contacts/send_verification_application/send_verification_application_binding.dart';
import '../pages/contacts/send_verification_application/send_verification_application_view.dart';
import '../pages/contacts/user_profile_panel/friend_setup/friend_setup_binding.dart';
import '../pages/contacts/user_profile_panel/friend_setup/friend_setup_view.dart';
import '../pages/contacts/user_profile_panel/personal_info/personal_info_binding.dart';
import '../pages/contacts/user_profile_panel/personal_info/personal_info_view.dart';
import '../pages/contacts/user_profile_panel/set_remark/set_remark_binding.dart';
import '../pages/contacts/user_profile_panel/set_remark/set_remark_view.dart';
import '../pages/contacts/user_profile_panel/user_profile _panel_binding.dart';
import '../pages/contacts/user_profile_panel/user_profile _panel_view.dart';
import '../pages/forget_password/forget_password_binding.dart';
import '../pages/forget_password/forget_password_view.dart';
import '../pages/forget_password/reset_password/reset_password_binding.dart';
import '../pages/forget_password/reset_password/reset_password_view.dart';
import '../pages/global_search/expand_chat_history/expand_chat_history_binding.dart';
import '../pages/global_search/expand_chat_history/expand_chat_history_view.dart';
import '../pages/global_search/global_search_binding.dart';
import '../pages/global_search/global_search_view.dart';
import '../pages/home/home_binding.dart';
import '../pages/home/home_view.dart';
import '../pages/login/login_binding.dart';
import '../pages/login/login_view.dart';
import '../pages/mine/about_us/about_us_binding.dart';
import '../pages/mine/about_us/about_us_view.dart';
import '../pages/mine/call_audio_debug/call_audio_debug_binding.dart';
import '../pages/mine/call_audio_debug/call_audio_debug_view.dart';
import '../pages/mine/account_setup/account_setup_binding.dart';
import '../pages/mine/account_setup/account_setup_view.dart';
import '../pages/mine/appearance_language_setup/appearance_language_setup_binding.dart';
import '../pages/mine/appearance_language_setup/appearance_language_setup_view.dart';
import '../pages/mine/chat_notification_setup/chat_notification_setup_binding.dart';
import '../pages/mine/chat_notification_setup/chat_notification_setup_view.dart';
import '../pages/mine/privacy_security_setup/privacy_security_setup_binding.dart';
import '../pages/mine/privacy_security_setup/privacy_security_setup_view.dart';
import '../pages/mine/blacklist/blacklist_binding.dart';
import '../pages/mine/blacklist/blacklist_view.dart';
import '../pages/mine/change_password/change_password_binding.dart';
import '../pages/mine/change_password/change_password_view.dart';
import '../pages/mine/edit_my_info/edit_my_info_binding.dart';
import '../pages/mine/edit_my_info/edit_my_info_view.dart';
import '../pages/mine/language_setup/language_setup_binding.dart';
import '../pages/mine/language_setup/language_setup_view.dart';
import '../pages/mine/theme_setup/theme_setup_binding.dart';
import '../pages/mine/theme_setup/theme_setup_view.dart';
import '../pages/mine/my_info/my_info_binding.dart';
import '../pages/mine/my_info/my_info_view.dart';
import '../pages/mine/my_qrcode/my_qrcode_binding.dart';
import '../pages/mine/my_qrcode/my_qrcode_view.dart';
import '../pages/moments/feed/moments_feed_binding.dart';
import '../pages/moments/feed/moments_feed_view.dart';
import '../pages/moments/notifications/moments_notifications_binding.dart';
import '../pages/moments/notifications/moments_notifications_view.dart';
import '../pages/moments/publish/moments_publish_binding.dart';
import '../pages/moments/publish/moments_publish_view.dart';
import '../pages/register/register_binding.dart';
import '../pages/register/register_view.dart';
import '../pages/register/set_password/set_password_binding.dart';
import '../pages/register/set_password/set_password_view.dart';
import '../pages/register/set_self_info/set_self_info_binding.dart';
import '../pages/register/set_self_info/set_self_info_view.dart';
import '../pages/register/verify_phone/verify_phone_binding.dart';
import '../pages/register/verify_phone/verify_phone_view.dart';
import '../pages/splash/splash_binding.dart';
import '../pages/splash/splash_view.dart';
import '../pages/workbench/workbench_binding.dart';
import '../pages/workbench/workbench_view.dart';

part 'app_routes.dart';

class AppPages {
  static _pageBuilder({
    required String name,
    required GetPageBuilder page,
    Bindings? binding,
    bool preventDuplicates = true,
    bool popGesture = true,
  }) =>
      GetPage(
        name: name,
        page: page,
        binding: binding,
        preventDuplicates: preventDuplicates,
        transition: Transition.cupertino,
        popGesture: popGesture,
      );

  static final routes = <GetPage>[
    _pageBuilder(
      name: AppRoutes.splash,
      page: () => SplashPage(),
      binding: SplashBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.login,
      page: () => LoginPage(),
      binding: LoginBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.home,
      page: () => HomePage(),
      binding: HomeBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.moments,
      page: () => MomentsFeedPage(),
      binding: MomentsFeedBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.momentsPublish,
      page: () => MomentsPublishPage(),
      binding: MomentsPublishBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.momentsNotifications,
      page: () => MomentsNotificationsPage(),
      binding: MomentsNotificationsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.workbench,
      page: () => WorkbenchPage(),
      binding: WorkbenchBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.chat,
      page: () => ChatPage(),
      binding: ChatBinding(),
      preventDuplicates: false,
    ),
    _pageBuilder(
      name: AppRoutes.chatReadDetail,
      page: () => ChatReadDetailPage(),
      binding: ChatReadDetailBinding(),
      preventDuplicates: false,
    ),
    _pageBuilder(
      name: AppRoutes.mergeMessageDetail,
      page: () => MergeMessageDetailPage(),
      binding: MergeMessageDetailBinding(),
      preventDuplicates: false,
    ),
    _pageBuilder(
      name: AppRoutes.groupAnnouncementDetail,
      page: () => GroupAnnouncementDetailPage(),
      binding: GroupAnnouncementDetailBinding(),
      preventDuplicates: false,
    ),
    _pageBuilder(
      name: AppRoutes.chatSetup,
      page: () => ChatSetupPage(),
      binding: ChatSetupBinding(),
      popGesture: false,
    ),
    _pageBuilder(
      name: AppRoutes.addContactsMethod,
      page: () => AddContactsMethodPage(),
      binding: AddContactsMethodBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.addContactsBySearch,
      page: () => AddContactsBySearchPage(),
      binding: AddContactsBySearchBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.userProfilePanel,
      page: () => UserProfilePanelPage(),
      binding: UserProfilePanelBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.personalInfo,
      page: () => PersonalInfoPage(),
      binding: PersonalInfoBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.friendSetup,
      page: () => FriendSetupPage(),
      binding: FriendSetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.setFriendRemark,
      page: () => SetFriendRemarkPage(),
      binding: SetFriendRemarkBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.sendVerificationApplication,
      page: () => SendVerificationApplicationPage(),
      binding: SendVerificationApplicationBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.groupProfilePanel,
      page: () => GroupProfilePanelPage(),
      binding: GroupProfilePanelBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.myInfo,
      page: () => MyInfoPage(),
      binding: MyInfoBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.editMyInfo,
      page: () => EditMyInfoPage(),
      binding: EditMyInfoBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.myQrcode,
      page: () => MyQrcodePage(),
      binding: MyQrcodeBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.accountSetup,
      page: () => AccountSetupPage(),
      binding: AccountSetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.chatNotificationSetup,
      page: () => ChatNotificationSetupPage(),
      binding: ChatNotificationSetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.privacySecuritySetup,
      page: () => PrivacySecuritySetupPage(),
      binding: PrivacySecuritySetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.appearanceLanguageSetup,
      page: () => AppearanceLanguageSetupPage(),
      binding: AppearanceLanguageSetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.changePassword,
      page: () => ChangePasswordPage(),
      binding: ChangePasswordBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.blacklist,
      page: () => BlacklistPage(),
      binding: BlacklistBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.languageSetup,
      page: () => LanguageSetupPage(),
      binding: LanguageSetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.themeSetup,
      page: () => ThemeSetupPage(),
      binding: ThemeSetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.aboutUs,
      page: () => AboutUsPage(),
      binding: AboutUsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.callAudioDebug,
      page: () => CallAudioDebugPage(),
      binding: CallAudioDebugBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.groupChatSetup,
      page: () => GroupSetupPage(),
      binding: GroupSetupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.groupManage,
      page: () => GroupManagePage(),
      binding: GroupManageBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.editGroupName,
      page: () => EditGroupNamePage(),
      binding: EditGroupNameBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.groupMemberList,
      page: () => GroupMemberListPage(),
      binding: GroupMemberListBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.searchGroupMember,
      page: () => SearchGroupMemberPage(),
      binding: SearchGroupMemberBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.groupQrcode,
      page: () => GroupQrcodePage(),
      binding: GroupQrcodeBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.friendRequests,
      page: () => FriendRequestsPage(),
      binding: FriendRequestsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.processFriendRequests,
      page: () => ProcessFriendRequestsPage(),
      binding: ProcessFriendRequestsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.groupRequests,
      page: () => GroupRequestsPage(),
      binding: GroupRequestsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.processGroupRequests,
      page: () => ProcessGroupRequestsPage(),
      binding: ProcessGroupRequestsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.friendList,
      page: () => FriendListPage(),
      binding: FriendListBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.groupList,
      page: () => GroupListPage(),
      binding: GroupListBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.scan,
      page: () => ScanPage(),
      binding: ScanBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.selectContacts,
      page: () => SelectContactsPage(),
      binding: SelectContactsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.selectContactsFromFriends,
      page: () => SelectContactsFromFriendsPage(),
      binding: SelectContactsFromFriendsBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.selectContactsFromGroup,
      page: () => SelectContactsFromGroupPage(),
      binding: SelectContactsFromGroupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.selectContactsFromSearch,
      page: () => SelectContactsFromSearchPage(),
      binding: SelectContactsFromSearchBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.createGroup,
      page: () => CreateGroupPage(),
      binding: CreateGroupBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.globalSearch,
      page: () => GlobalSearchPage(),
      binding: GlobalSearchBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.expandChatHistory,
      page: () => ExpandChatHistoryPage(),
      binding: ExpandChatHistoryBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.register,
      page: () => RegisterPage(),
      binding: RegisterBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.verifyPhone,
      page: () => VerifyPhonePage(),
      binding: VerifyPhoneBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.setPassword,
      page: () => SetPasswordPage(),
      binding: SetPasswordBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.setSelfInfo,
      page: () => SetSelfInfoPage(),
      binding: SetSelfInfoBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.forgetPassword,
      page: () => ForgetPasswordPage(),
      binding: ForgetPasswordBinding(),
    ),
    _pageBuilder(
      name: AppRoutes.resetPassword,
      page: () => ResetPasswordPage(),
      binding: ResetPasswordBinding(),
    ),
  ];
}
