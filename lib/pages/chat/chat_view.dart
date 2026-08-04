import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_logic.dart';
import 'voice_record_bar.dart';
import '../../routes/app_navigator.dart';

class ChatPage extends StatelessWidget {
  final logic = Get.find<ChatLogic>(tag: GetTags.chat);

  ChatPage({super.key});

  Widget _buildItemView(Message message, {required bool showReadTag}) {
    final item = ChatItemView(
      key: logic.itemKey(message),
      message: message,
      showReadTag: showReadTag,
      textScaleFactor: logic.scaleFactor.value,
      allAtMap: logic.getAtMapping(message),
      timelineStr: logic.getShowTime(message),
      sendStatusSubject: logic.sendStatusSub,
      leftNickname: logic.getNewestNickname(message),
      leftFaceUrl: logic.getNewestFaceURL(message),
      rightNickname: logic.senderName,
      rightFaceUrl: OpenIM.iMManager.userInfo.faceURL,
      showLeftNickname: !logic.isSingleChat,
      showRightNickname: !logic.isSingleChat,
      onFailedToResend: () => logic.failedResend(message),
      onClickItemView: () => logic.isMultiSelectMode.value
          ? logic.toggleSelectedMessage(message)
          : logic.parseClickEvent(message),
      visibilityChange: (msg, visible) {
        logic.markMessageAsRead(message, visible);
      },
      onLongPressRightAvatar: () {},
      onTapLeftAvatar: () {
        logic.onTapLeftAvatar(message);
      },
      onTapReadTag: () => logic.onTapReadTag(message),
      onVisibleTrulyText: (text) {
        logic.copyTextMap[message.clientMsgID] = text;
      },
      customTypeBuilder: _buildCustomTypeItemView,
      patterns: <MatchPattern>[
        MatchPattern(
          type: PatternType.email,
          onTap: logic.clickLinkText,
        ),
        MatchPattern(
          type: PatternType.url,
          onTap: logic.clickLinkText,
        ),
        MatchPattern(
          type: PatternType.mobile,
          onTap: logic.clickLinkText,
        ),
        MatchPattern(
          type: PatternType.tel,
          onTap: logic.clickLinkText,
        ),
      ],
      mediaItemBuilder: (context, message) {
        return _buildMediaItem(context, message);
      },
      onTapUserProfile: handleUserProfileTap,
      onTapMergeMessage: (message) {
        final merge = message.mergeElem;
        AppNavigator.startMergeMessageDetail(
          title: IMUtils.isNotNullEmptyStr(merge?.title)
              ? merge!.title!
              : StrRes.chatRecord,
          messages: merge?.multiMessage ?? const [],
        );
      },
    );

    if (logic.isMultiSelectMode.value) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => logic.toggleSelectedMessage(message),
        child: Row(
          children: [
            SizedBox(
              width: 48.w,
              child: Center(
                child: ChatRadio(checked: logic.isSelectedMessage(message)),
              ),
            ),
            Expanded(child: item),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => logic.showMessageActionSheet(message),
      child: item,
    );
  }

  void handleUserProfileTap(
      ({
        String userID,
        String name,
        String? faceURL,
        String? groupID
      }) userProfile) {
    final userInfo = UserInfo(
        userID: userProfile.userID,
        nickname: userProfile.name,
        faceURL: userProfile.faceURL);
    logic.viewUserInfo(userInfo);
  }

  Widget? _buildMediaItem(BuildContext context, Message message) {
    if (message.contentType != MessageType.picture &&
        message.contentType != MessageType.video) {
      return null;
    }

    return GestureDetector(
      onTap: () async {
        try {
          IMUtils.previewMediaFile(
              context: context,
              message: message,
              onAutoPlay: (index) {
                return !logic.playOnce;
              },
              muted: logic.rtcIsBusy,
              onPageChanged: (index) {
                logic.playOnce = true;
              },
              onEdited: (path) async {
                try {
                  await logic.sendPicture(path: path);
                } catch (e) {
                  IMViews.showToast(e.toString());
                }
              }).then((value) {
            logic.playOnce = false;
          });
        } catch (e) {
          IMViews.showToast(e.toString());
        }
      },
      child: Hero(
        tag: message.clientMsgID!,
        child: _buildMediaContent(message),
        placeholderBuilder:
            (BuildContext context, Size heroSize, Widget child) => child,
      ),
    );
  }

  Widget _buildMediaContent(Message message) {
    final isOutgoing = message.sendID == OpenIM.iMManager.userID;

    if (message.isVideoType) {
      return const SizedBox();
    } else {
      return ChatPictureView(
        isISend: isOutgoing,
        message: message,
      );
    }
  }

  CustomTypeInfo? _buildCustomTypeItemView(
      BuildContext context, Message message) {
    final data = IMUtils.parseCustomMessage(message);
    if (null != data) {
      final viewType = data['viewType'];
      if (viewType == CustomMessageType.call) {
        final type = data['type'];
        final content = data['content'];
        final view = ChatCallItemView(type: type, content: content);
        return CustomTypeInfo(view);
      } else if (viewType == CustomMessageType.deletedByFriend ||
          viewType == CustomMessageType.blockedByFriend) {
        final view = ChatFriendRelationshipAbnormalHintView(
          name: logic.nickname.value,
          onTap: logic.sendFriendVerification,
          blockedByFriend: viewType == CustomMessageType.blockedByFriend,
          deletedByFriend: viewType == CustomMessageType.deletedByFriend,
        );
        return CustomTypeInfo(view, false, false);
      } else if (viewType == CustomMessageType.removedFromGroup) {
        return CustomTypeInfo(
          StrRes.removedFromGroupHint.toText..style = Styles.ts_8E9AB0_12sp,
          false,
          false,
        );
      } else if (viewType == CustomMessageType.groupDisbanded) {
        return CustomTypeInfo(
          StrRes.groupDisbanded.toText..style = Styles.ts_8E9AB0_12sp,
          false,
          false,
        );
      }
    }
    return null;
  }

  Widget? get _groupCallHintView => null;

  Widget _buildBottomView() {
    if (logic.isMultiSelectMode.value) {
      return _buildMultiSelectBar();
    }
    return ChatInputBox(
      forceCloseToolboxSub: logic.forceCloseToolbox,
      controller: logic.inputCtrl,
      focusNode: logic.focusNode,
      isNotInGroup: logic.isInvalidGroup,
      quoteContent: logic.quoteContent,
      onClearQuote: logic.clearQuoteMessage,
      directionalText: logic.directionalText(),
      onCloseDirectional: logic.onClearDirectional,
      onSend: (v) => logic.sendTextMsg(),
      toolbox: ChatToolBox(
        onTapAlbum: logic.onTapAlbum,
        onTapCall: logic.callVideo,
        onTapFile: logic.onTapFile,
        onTapCard: logic.onTapCarte,
        onTapCamera: logic.onTapCamera,
        onTapLocation: logic.onTapLocation,
      ),
      voiceRecordBar: VoiceRecordBar(
        onRecordComplete: (path, duration) => logic.sendVoice(
          path: path,
          duration: duration,
        ),
      ),
    );
  }

  Widget _buildMultiSelectBar() => Container(
        height: 66.h,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          boxShadow: [
            BoxShadow(
              offset: Offset(0, -1.h),
              blurRadius: 4.r,
              spreadRadius: 1.r,
              color: Styles.c_000000_opacity4,
            ),
          ],
        ),
        child: Row(
          children: [
            InkWell(
              onTap: logic.selectedMessages.isEmpty
                  ? null
                  : logic.forwardSelectedMessages,
              child: Opacity(
                opacity: logic.selectedMessages.isEmpty ? .4 : 1,
                child: Row(
                  children: [
                    ImageRes.multiBoxForward.toImage
                      ..width = 28.w
                      ..height = 28.h,
                    8.horizontalSpace,
                    '${StrRes.mergeForward} (${logic.selectedMessages.length})'
                        .toText
                      ..style = Styles.ts_0089FF_17sp,
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildGroupAnnouncementView(bool showAnn, String annText) {
    if (!showAnn) return const SizedBox.shrink();
    return TopNoticeView(
      content: annText,
      onPreview: logic.previewAnnouncement,
      onClose: logic.closeAnnouncement,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (_) => WillPopScope(
        onWillPop: logic.willPop(),
        child: Scaffold(
          backgroundColor: Styles.c_F0F2F6,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(48.h),
            child: Obx(() => TitleBar.chat(
                  title: logic.nickname.value,
                  member: logic.typingStatus.value.isEmpty
                      ? logic.memberStr
                      : ' ${logic.typingStatus.value}',
                  subtitle: logic.typingStatus.value.isEmpty
                      ? (logic.isSingleChat
                          ? logic.onlineStatusDesc.value
                          : null)
                      : null,
                  isMultiModel: logic.isMultiSelectMode.value,
                  onCloseMultiModel: logic.exitMultiSelectMode,
                  onClickMoreBtn: logic.chatSetup,
                  onClickCallBtn:
                      logic.isMultiSelectMode.value ? null : logic.callVoice,
                )),
          ),
          body: SafeArea(
            child: Obx(() {
              final showAnn = logic.isGroupChat && logic.showAnnouncement.value;
              final annText = logic.announcement.value;
              return WaterMarkBgView(
                text: '',
                path: logic.background.value,
                backgroundColor: Styles.c_FFFFFF,
                floatView: _groupCallHintView,
                topView: _buildGroupAnnouncementView(showAnn, annText),
                bottomView: _buildBottomView(),
                child: ChatListView(
                  onTouch: () => logic.closeToolbox(),
                  itemCount: logic.messageList.length,
                  initialScrollToBottomLoadMore: logic.hasMoreHistory,
                  autoLoadInitialMessages: logic.shouldAutoLoadInitialMessages,
                  controller: logic.scrollController,
                  onScrollToBottomLoad: logic.onScrollToBottomLoad,
                  onScrollToTop: logic.onScrollToTop,
                  itemBuilder: (_, index) {
                    final message = logic.indexOfMessage(index);
                    return Obx(() {
                      logic.isMultiSelectMode.value;
                      logic.scaleFactor.value;
                      final showReadTag = logic.shouldShowReadTag(message);
                      return _buildItemView(message, showReadTag: showReadTag);
                    });
                  },
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
