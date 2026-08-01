import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:search_keyword_text/search_keyword_text.dart';
import 'package:sprintf/sprintf.dart';

import 'global_search_logic.dart';

class GlobalSearchPage extends StatelessWidget {
  final logic = Get.find<GlobalSearchLogic>();

  GlobalSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TouchCloseSoftKeyboard(
      child: Scaffold(
        appBar: TitleBar.search(
          controller: logic.searchCtrl,
          focusNode: logic.focusNode,
          onSubmitted: (_) => logic.search(),
          onCleared: logic.onSearchCleared,
          onChanged: logic.onSearchChanged,
        ),
        backgroundColor: Styles.pageBackground,
        body: Obx(
          () => Column(
            children: [
              CustomTabBar(
                labels: logic.tabs,
                index: logic.index.value,
                onTabChanged: logic.switchTab,
                showUnderline: true,
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (logic.inputKeyword.value.isEmpty) return _buildHintView();
    if (logic.isSearching.value) return _buildSearchingView();
    if (logic.isSearchNotResult) return _buildEmptyView();
    switch (logic.index.value) {
      case 1:
        return _buildContactList(logic.contactsList);
      case 2:
        return _buildGroupList(logic.groupList);
      case 3:
        return _buildChatHistoryList(logic.textSearchResultItems);
      case 4:
        return _buildFileList(logic.fileMessageList);
      default:
        return _buildAllList();
    }
  }

  Widget _buildAllList() => ListView(
        children: [
          _buildSection(
            title: StrRes.globalSearchContacts,
            showMoreText: StrRes.seeMoreRelatedContacts,
            showMore: logic.contactsList.length > 3,
            onShowMore: () => logic.switchTab(1),
            children:
                logic.contactsList.take(3).map(_buildContactItem).toList(),
          ),
          _buildSection(
            title: StrRes.globalSearchGroup,
            showMoreText: StrRes.seeMoreRelatedGroup,
            showMore: logic.groupList.length > 3,
            onShowMore: () => logic.switchTab(2),
            children: logic.groupList.take(3).map(_buildGroupItem).toList(),
          ),
          _buildSection(
            title: StrRes.globalSearchChatHistory,
            showMoreText: StrRes.seeMoreRelatedChatHistory,
            showMore: logic.textSearchResultItems.length > 3,
            onShowMore: () => logic.switchTab(3),
            children: logic.textSearchResultItems
                .take(3)
                .map(_buildChatHistoryItem)
                .toList(),
          ),
          _buildSection(
            title: StrRes.globalSearchChatFile,
            showMoreText: StrRes.seeMoreRelatedFile,
            showMore: logic.fileMessageList.length > 3,
            onShowMore: () => logic.switchTab(4),
            children:
                logic.fileMessageList.take(3).map(_buildFileItem).toList(),
          ),
        ],
      );

  Widget _buildSection({
    required String title,
    required List<Widget> children,
    String? showMoreText,
    bool showMore = false,
    VoidCallback? onShowMore,
  }) {
    if (children.isEmpty) return const SizedBox();
    return Container(
      margin: EdgeInsets.only(top: 10.h),
      color: Styles.c_FFFFFF,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: title.toText..style = Styles.ts_0C1C33_17sp_medium,
          ),
          ...children,
          if (showMore && showMoreText != null)
            InkWell(
              onTap: onShowMore,
              child: Container(
                height: 44.h,
                alignment: Alignment.center,
                child: showMoreText.toText..style = Styles.ts_0089FF_14sp,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContactList(List<dynamic> list) => list.isEmpty
      ? _buildEmptyView()
      : ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, index) => _buildContactItem(list[index]),
        );

  Widget _buildGroupList(List<GroupInfo> list) => list.isEmpty
      ? _buildEmptyView()
      : ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, index) => _buildGroupItem(list[index]),
        );

  Widget _buildChatHistoryList(List<SearchResultItems> list) => list.isEmpty
      ? _buildEmptyView()
      : ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, index) => _buildChatHistoryItem(list[index]),
        );

  Widget _buildFileList(List<Message> list) => list.isEmpty
      ? _buildEmptyView()
      : ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, index) => _buildFileItem(list[index]),
        );

  Widget _buildContactItem(dynamic info) => _buildAvatarItem(
        faceURL: logic.parseFaceURL(info),
        title: logic.parseNickname(info) ?? '',
        isGroup: false,
        onTap: () => logic.viewContact(info),
      );

  Widget _buildGroupItem(GroupInfo info) => _buildAvatarItem(
        faceURL: info.faceURL,
        title: info.groupName ?? '',
        subtitle: info.groupID,
        isGroup: true,
        onTap: () => logic.viewGroup(info),
      );

  Widget _buildChatHistoryItem(SearchResultItems item) {
    final messageList = item.messageList ?? [];
    final firstMessage = messageList.isEmpty ? null : messageList.first;
    final summary = firstMessage == null ? '' : IMUtils.parseMsg(firstMessage);
    return _buildAvatarItem(
      faceURL: item.faceURL,
      title: item.showName ?? '',
      subtitle: summary,
      trailing: sprintf(StrRes.relatedChatHistory,
          [item.messageCount ?? item.messageList?.length ?? 0]).toText
        ..style = Styles.ts_8E9AB0_14sp,
      isGroup: _isGroupConversationType(item.conversationType),
      onTap: () => logic.viewSearchResultItems(item),
    );
  }

  Widget _buildFileItem(Message message) => _buildAvatarItem(
        faceURL: message.senderFaceUrl,
        title: message.fileElem?.fileName ?? StrRes.file,
        subtitle: message.senderNickname,
        onTap: () {
          final item = SearchResultItems(
            conversationID: _conversationIDOf(message),
            messageCount: 1,
            messageList: [message],
          );
          logic.viewMessage(item, message);
        },
      );

  String? _conversationIDOf(Message message) {
    final id = _isGroupConversationType(message.sessionType)
        ? message.groupID
        : (message.sendID == OpenIM.iMManager.userID
            ? message.recvID
            : message.sendID);
    if (id == null) return null;
    return _isGroupConversationType(message.sessionType) ? 'sg_$id' : 'si_$id';
  }

  bool _isGroupConversationType(int? conversationType) =>
      conversationType == 2 || conversationType == 3;

  Widget _buildAvatarItem({
    required String title,
    String? faceURL,
    String? subtitle,
    Widget? trailing,
    bool isGroup = false,
    VoidCallback? onTap,
  }) =>
      Ink(
        height: 64.h,
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                AvatarView(url: faceURL, text: title, isGroup: isGroup),
                10.horizontalSpace,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SearchKeywordText(
                        text: title,
                        keyText: logic.searchKey,
                        style: Styles.ts_0C1C33_17sp,
                        keyStyle: Styles.ts_0089FF_17sp,
                      ),
                      if (IMUtils.isNotNullEmptyStr(subtitle)) ...[
                        4.verticalSpace,
                        (subtitle ?? '').toText
                          ..style = Styles.ts_8E9AB0_14sp
                          ..maxLines = 1
                          ..overflow = TextOverflow.ellipsis,
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      );

  Widget _buildHintView() => SizedBox(
        width: 1.sw,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            44.verticalSpace,
            StrRes.quicklyFindChatHistory.toText..style = Styles.ts_8E9AB0_17sp,
          ],
        ),
      );

  Widget _buildSearchingView() => SizedBox(
        width: 1.sw,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            44.verticalSpace,
            SizedBox(
              width: 20.w,
              height: 20.w,
              child: CircularProgressIndicator(
                strokeWidth: 2.w,
                color: Styles.c_0089FF,
              ),
            ),
          ],
        ),
      );

  Widget _buildEmptyView() => SizedBox(
        width: 1.sw,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            44.verticalSpace,
            StrRes.searchNotFound.toText..style = Styles.ts_8E9AB0_17sp,
          ],
        ),
      );
}
