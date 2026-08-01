import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ChatReadDetailLogic extends GetxController {
  late final Message message;

  final readList = <GroupMembersInfo>[].obs;
  final unreadList = <GroupMembersInfo>[].obs;
  final hasReadCount = 0.obs;
  final unreadCount = 0.obs;
  final totalMemberCount = 0.obs;
  final loading = true.obs;
  final failed = false.obs;

  static const _filterRead = 0;
  static const _filterUnread = 1;

  String? get _conversationID => Get.arguments['conversationID'] as String?;

  @override
  void onInit() {
    super.onInit();
    message = Get.arguments['message'] as Message;
    _loadSummary();
    loadReaders();
  }

  void _loadSummary() {
    final info = message.attachedInfoElem?.groupHasReadInfo;
    hasReadCount.value = info?.hasReadCount ?? 0;
    unreadCount.value = info?.unreadCount ?? 0;
    totalMemberCount.value = hasReadCount.value + unreadCount.value;
  }

  Future<void> loadReaders() async {
    final conversationID = _conversationID;
    final clientMsgID = message.clientMsgID;
    final seq = message.seq ?? 0;
    final groupID = message.groupID;
    if (conversationID == null ||
        conversationID.isEmpty ||
        clientMsgID == null ||
        clientMsgID.isEmpty ||
        seq <= 0 ||
        groupID == null ||
        groupID.isEmpty) {
      loading.value = false;
      failed.value = true;
      return;
    }
    loading.value = true;
    failed.value = false;
    try {
      final results = await Future.wait([
        Apis.getGroupMessageReaderList(
          conversationID: conversationID,
          clientMsgID: clientMsgID,
          seq: seq,
          filter: _filterRead,
        ),
        Apis.getGroupMessageReaderList(
          conversationID: conversationID,
          clientMsgID: clientMsgID,
          seq: seq,
          filter: _filterUnread,
        ),
      ]);
      final read = results[0];
      final unread = results[1];
      if (read == null || unread == null) {
        failed.value = true;
        return;
      }
      hasReadCount.value = read.hasReadCount;
      unreadCount.value = read.unreadCount;
      totalMemberCount.value = read.hasReadCount + read.unreadCount;
      final members = await Future.wait([
        _resolveMembers(groupID, read.userIDs),
        _resolveMembers(groupID, unread.userIDs),
      ]);
      readList.assignAll(members[0]);
      unreadList.assignAll(members[1]);
    } catch (e, s) {
      Logger.print('loadReaders error: e:$e s:$s');
      failed.value = true;
    } finally {
      loading.value = false;
    }
  }

  Future<List<GroupMembersInfo>> _resolveMembers(
      String groupID, List<String> userIDs) async {
    if (userIDs.isEmpty) return [];
    try {
      final members = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupID: groupID,
        userIDList: userIDs,
      );
      final map = {for (final m in members) m.userID: m};
      return userIDs
          .map((id) =>
              map[id] ?? GroupMembersInfo(userID: id, nickname: id))
          .toList();
    } catch (_) {
      return userIDs
          .map((id) => GroupMembersInfo(userID: id, nickname: id))
          .toList();
    }
  }
}
