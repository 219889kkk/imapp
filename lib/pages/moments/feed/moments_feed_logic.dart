import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/edit_my_info/edit_my_info_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../../core/controller/im_controller.dart';
import 'moments_comment_input.dart';

class MomentsFeedLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final list = <MomentPost>[].obs;
  final coverUrl = ''.obs;
  final refreshController = RefreshController();
  String? cursor;
  bool hasMore = true;

  String get selfNickname => OpenIM.iMManager.userInfo.nickname ?? '';

  String? get selfFaceUrl => OpenIM.iMManager.userInfo.faceURL;

  String get selfSignature =>
      imLogic.userInfo.value.signature?.trim().isNotEmpty == true
          ? imLogic.userInfo.value.signature!.trim()
          : '';

  @override
  void onReady() {
    loadMomentProfile();
    _loadSelfProfile();
    refreshMoments();
    super.onReady();
  }

  @override
  void onClose() {
    refreshController.dispose();
    super.onClose();
  }

  Future<void> refreshMoments() async {
    try {
      cursor = null;
      final resp = await Apis.getMomentsFeed(cursor: cursor);
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
      final resp = await Apis.getMomentsFeed(cursor: cursor);
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

  Future<void> publish() async {
    final result = await AppNavigator.startMomentsPublish();
    if (result == true) {
      refreshMoments();
    }
  }

  void notifications() => AppNavigator.startMomentsNotifications();

  Future<void> loadMomentProfile() async {
    final profile = await Apis.getMomentProfile(OpenIM.iMManager.userID);
    coverUrl.value = profile.coverUrl ?? '';
  }

  Future<void> _loadSelfProfile() async {
    final info = await Apis.queryMyFullInfo();
    if (info != null) {
      imLogic.userInfo.update((val) {
        val?.signature = info.signature;
      });
    }
  }

  void editSignature() {
    AppNavigator.startEditMyInfo(
      attr: EditAttr.signature,
      maxLength: 30,
    );
  }

  void changeCover() {
    IMViews.openPhotoSheet(
      crop: false,
      toUrl: true,
      quality: 90,
      onData: (_, url) async {
        if (url is! String || url.isEmpty) return;
        final profile = await Apis.updateMomentCover(url);
        coverUrl.value = profile.coverUrl ?? url;
      },
    );
  }

  Future<void> toggleLike(MomentPost post) async {
    final updated = post.isLiked
        ? await Apis.unlikeMomentPost(post.postID)
        : await Apis.likeMomentPost(post.postID);
    _replacePost(updated);
  }

  Future<void> comment(MomentPost post) async {
    final content = await MomentsCommentInput.show(Get.context!);
    if (content == null || content.isEmpty) return;
    final comment = await Apis.createMomentComment(
      postID: post.postID,
      content: content,
    );
    post.comments.add(comment);
    list.refresh();
  }

  Future<void> replyComment(MomentPost post, MomentComment comment) async {
    final content = await MomentsCommentInput.show(
      Get.context!,
      replyToNickname: comment.nickname,
    );
    if (content == null || content.isEmpty) return;
    final reply = await Apis.createMomentComment(
      postID: post.postID,
      content: content,
      replyToUserID: comment.userID,
      replyToNickname: comment.nickname,
    );
    post.comments.add(reply);
    list.refresh();
  }

  Future<void> deletePost(MomentPost post) async {
    final confirm = await Get.dialog(CustomDialog(title: StrRes.delete));
    if (confirm != true) return;
    await Apis.deleteMomentPost(post.postID);
    list.removeWhere((e) => e.postID == post.postID);
  }

  Future<void> deleteComment(
    MomentPost post,
    MomentComment comment,
  ) async {
    final confirm = await Get.dialog(CustomDialog(title: StrRes.delete));
    if (confirm != true) return;
    await Apis.deleteMomentComment(comment.commentID);
    post.comments.removeWhere((e) => e.commentID == comment.commentID);
    list.refresh();
  }

  bool canDelete(MomentPost post) =>
      post.author.userID == OpenIM.iMManager.userID;

  bool canDeleteComment(MomentPost post, MomentComment comment) =>
      canDelete(post) || comment.userID == OpenIM.iMManager.userID;

  void _replacePost(MomentPost post) {
    final index = list.indexWhere((e) => e.postID == post.postID);
    if (index >= 0) {
      list[index] = post;
    }
  }
}
