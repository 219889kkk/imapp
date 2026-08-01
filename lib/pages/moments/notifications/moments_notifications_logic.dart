import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

class MomentsNotificationsLogic extends GetxController {
  final list = <MomentNotification>[].obs;
  final refreshController = RefreshController();
  String? cursor;
  bool hasMore = true;

  @override
  void onReady() {
    refreshNotifications();
    Apis.markMomentNotificationsRead();
    super.onReady();
  }

  @override
  void onClose() {
    refreshController.dispose();
    super.onClose();
  }

  Future<void> refreshNotifications() async {
    try {
      cursor = null;
      final resp = await Apis.getMomentNotifications(cursor: cursor);
      list.assignAll(resp.list);
      cursor = resp.cursor;
      hasMore = resp.hasMore;
      refreshController.refreshCompleted();
      hasMore
          ? refreshController.loadComplete()
          : refreshController.loadNoData();
    } catch (_) {
      refreshController.refreshFailed();
    }
  }

  Future<void> loadMore() async {
    if (!hasMore) {
      refreshController.loadNoData();
      return;
    }
    try {
      final resp = await Apis.getMomentNotifications(cursor: cursor);
      list.addAll(resp.list);
      cursor = resp.cursor;
      hasMore = resp.hasMore;
      hasMore
          ? refreshController.loadComplete()
          : refreshController.loadNoData();
    } catch (_) {
      refreshController.loadFailed();
    }
  }

  String titleFor(MomentNotification notification) {
    switch (notification.type) {
      case MomentNotificationType.like:
        return StrRes.likedYou;
      case MomentNotificationType.reply:
      case MomentNotificationType.comment:
      default:
        return StrRes.commentedYou;
    }
  }
}
