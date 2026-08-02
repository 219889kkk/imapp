import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/theme_aware.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'moments_feed_logic.dart';

class MomentsFeedPage extends StatelessWidget {
  final logic = Get.find<MomentsFeedLogic>();

  MomentsFeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeAware(
      builder: (context) => Scaffold(
        backgroundColor: Styles.c_FFFFFF,
        body: Obx(
          () => SmartRefresher(
            controller: logic.refreshController,
            onRefresh: logic.refreshMoments,
            onLoading: logic.loadMore,
            enablePullUp: true,
            header: IMViews.buildHeader(),
            footer: IMViews.buildFooter(),
            child: ListView.builder(
              // SmartRefresher 不会注入 MediaQuery 的 scroll padding,
              // 手动留出底部悬浮玻璃 Dock 的高度,避免最后一条动态被遮挡
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: logic.list.isEmpty ? 2 : logic.list.length + 1,
              itemBuilder: (_, index) {
                if (index == 0) {
                  return _MomentsHeader(logic: logic);
                }
                if (logic.list.isEmpty) {
                  return SizedBox(
                    height: 220.h,
                    child: Center(
                      child: StrRes.noDynamic.toText
                        ..style = Styles.ts_8E9AB0_17sp,
                    ),
                  );
                }
                final post = logic.list[index - 1];
                return _MomentItemView(
                  post: post,
                  onLike: () => logic.toggleLike(post),
                  onComment: () => logic.comment(post),
                  onReplyComment: (comment) =>
                      logic.replyComment(post, comment),
                  onDelete: logic.canDelete(post)
                      ? () => logic.deletePost(post)
                      : null,
                  onDeleteComment: (comment) =>
                      logic.canDeleteComment(post, comment)
                          ? logic.deleteComment(post, comment)
                          : null,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MomentsHeader extends StatelessWidget {
  const _MomentsHeader({required this.logic});

  final MomentsFeedLogic logic;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320.h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: logic.changeCover,
            child: SizedBox(
              width: double.infinity,
              height: 250.h,
              child: Obx(() {
                final cover = logic.coverUrl.value;
                if (cover.isNotEmpty) {
                  return Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        ImageRes.workingCircleHeaderBg.toImage
                          ..fit = BoxFit.cover,
                  );
                }
                return ImageRes.workingCircleHeaderBg.toImage
                  ..fit = BoxFit.cover;
              }),
            ),
          ),
          Positioned(
            left: 16.w,
            right: 16.w,
            top: MediaQuery.of(context).padding.top + 14.h,
            child: Row(
              children: [
                StrRes.workingCircle.toText
                  ..style = Styles.ts_FFFFFF_20sp_medium,
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: logic.notifications,
                  child: ImageRes.workingCircleMessage.toImage
                    ..width = 28.w
                    ..height = 28.h,
                ),
                18.horizontalSpace,
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: logic.publish,
                  child: ImageRes.workingCirclePublish.toImage
                    ..width = 28.w
                    ..height = 28.h,
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 92.h,
              color: Styles.c_FFFFFF,
            ),
          ),
          Positioned(
            right: 92.w,
            bottom: 74.h,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 220.w),
              child: logic.selfNickname.toText
                ..style = Styles.ts_FFFFFF_17sp_semibold
                ..maxLines = 1
                ..overflow = TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            right: 16.w,
            bottom: 26.h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AvatarView(
                  width: 66.w,
                  height: 66.h,
                  text: logic.selfNickname,
                  url: logic.selfFaceUrl,
                  textStyle: Styles.ts_FFFFFF_17sp_medium,
                ),
                6.verticalSpace,
                Obx(
                  () => GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: logic.editSignature,
                    child: SizedBox(
                      width: 66.w,
                      child: (logic.selfSignature.isNotEmpty
                              ? logic.selfSignature
                              : StrRes.setSignature)
                          .toText
                        ..style = Styles.ts_8E9AB0_14sp
                        ..maxLines = 2
                        ..overflow = TextOverflow.ellipsis
                        ..textAlign = TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentItemView extends StatelessWidget {
  const _MomentItemView({
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onReplyComment,
    required this.onDeleteComment,
    this.onDelete,
  });

  final MomentPost post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final ValueChanged<MomentComment> onReplyComment;
  final ValueChanged<MomentComment> onDeleteComment;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Styles.c_FFFFFF,
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarView(
            width: 44.w,
            height: 44.h,
            text: post.author.nickname,
            url: post.author.faceURL,
          ),
          10.horizontalSpace,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                post.author.nickname.toText
                  ..style = Styles.ts_0C1C33_17sp_medium,
                if (post.content.isNotEmpty) 8.verticalSpace,
                if (post.content.isNotEmpty)
                  post.content.toText
                    ..style = Styles.ts_0C1C33_17sp
                    ..maxLines = 8
                    ..overflow = TextOverflow.ellipsis,
                if (post.mediaList.isNotEmpty) 10.verticalSpace,
                if (post.mediaList.isNotEmpty) _buildMediaGrid(),
                10.verticalSpace,
                Row(
                  children: [
                    _formatTime(post.createdAt).toText
                      ..style = Styles.ts_8E9AB0_12sp,
                    const Spacer(),
                    _MomentsMoreActionButton(
                      isLiked: post.isLiked,
                      showDelete: onDelete != null,
                      onLike: onLike,
                      onComment: onComment,
                      onDelete: onDelete,
                    ),
                  ],
                ),
                if (post.likeUsers.isNotEmpty || post.comments.isNotEmpty)
                  _buildInteractionView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    final count = post.mediaList.length > 9 ? 9 : post.mediaList.length;
    final itemSize = 80.w;
    return Wrap(
      spacing: 6.w,
      runSpacing: 6.h,
      children: List.generate(count, (index) {
        final media = post.mediaList[index];
        return GestureDetector(
          onTap: () => _previewMedia(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: Image.network(
              media.thumbUrl ?? media.url,
              width: itemSize,
              height: itemSize,
              fit: BoxFit.cover,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildInteractionView() => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 8.w,
            top: -5.h,
            child: CustomPaint(
              size: Size(10.w, 6.h),
              painter: _InteractionTrianglePainter(Styles.insetBackground),
            ),
          ),
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(top: 8.h),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: Styles.insetBackground,
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.likeUsers.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 2.h, right: 4.w),
                        child: Icon(
                          Icons.favorite_border,
                          size: 14.w,
                          color: Styles.c_6085B1,
                        ),
                      ),
                      Expanded(
                        child: post.likeUsers
                            .map((e) => e.nickname)
                            .join('、')
                            .toText
                          ..style = Styles.ts_6085B1_14sp,
                      ),
                    ],
                  ),
                if (post.likeUsers.isNotEmpty && post.comments.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: Styles.c_E8EAEF,
                    ),
                  ),
                ...post.comments.map(
                  (e) => GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => onReplyComment(e),
                    onLongPress: () => onDeleteComment(e),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 2.h),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: e.nickname,
                              style: Styles.ts_6085B1_14sp,
                            ),
                            if (e.replyToNickname?.isNotEmpty == true) ...[
                              TextSpan(
                                text: ' ${StrRes.reply} ',
                                style: Styles.ts_0C1C33_14sp,
                              ),
                              TextSpan(
                                text: e.replyToNickname,
                                style: Styles.ts_6085B1_14sp,
                              ),
                            ],
                            TextSpan(
                              text: ': ${e.content}',
                              style: Styles.ts_0C1C33_14sp,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  void _previewMedia(int index) {
    final sources = post.mediaList
        .map((e) => MediaSource(url: e.url, thumbnail: e.thumbUrl ?? e.url))
        .toList();
    IMUtils.previewUrlPicture(sources, currentIndex: index);
  }

  String _formatTime(int value) {
    final ms = value > 1000000000000 ? value : value * 1000;
    return IMUtils.getWorkMomentsTimeline(ms);
  }
}

class _MomentsMoreActionButton extends StatefulWidget {
  const _MomentsMoreActionButton({
    required this.isLiked,
    required this.showDelete,
    required this.onLike,
    required this.onComment,
    this.onDelete,
  });

  final bool isLiked;
  final bool showDelete;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback? onDelete;

  @override
  State<_MomentsMoreActionButton> createState() =>
      _MomentsMoreActionButtonState();
}

class _MomentsMoreActionButtonState extends State<_MomentsMoreActionButton> {
  final _popupKey = GlobalKey<OverlayPopupMenuButtonState>();

  void _handleAction(VoidCallback action) {
    _popupKey.currentState?.dismiss();
    action();
  }

  Widget _buildMenu() => Container(
        height: 36.h,
        decoration: BoxDecoration(
          color: Styles.insetBackground,
          borderRadius: BorderRadius.circular(4.r),
          border: Border.all(color: Styles.c_E8EAEF, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMenuAction(
              widget.isLiked ? StrRes.cancel : StrRes.like,
              () => _handleAction(widget.onLike),
            ),
            Container(
              width: 0.5,
              height: 18.h,
              color: Styles.c_E8EAEF,
            ),
            _buildMenuAction(
              StrRes.comment,
              () => _handleAction(widget.onComment),
            ),
            if (widget.showDelete) ...[
              Container(
                width: 0.5,
                height: 18.h,
                color: Styles.c_E8EAEF,
              ),
              _buildMenuAction(
                StrRes.delete,
                () => _handleAction(widget.onDelete!),
              ),
            ],
          ],
        ),
      );

  Widget _buildMenuAction(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          child: Center(
            child: label.toText..style = Styles.ts_0C1C33_14sp,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return OverlayPopupMenuButton(
      key: _popupKey,
      expandFromRight: true,
      builder: (_) => _buildMenu(),
      child: Container(
        width: 32.w,
        height: 20.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Styles.insetBackground,
          borderRadius: BorderRadius.circular(4.r),
        ),
        child: Icon(Icons.more_horiz, size: 18.w, color: Styles.c_6085B1),
      ),
    );
  }
}

class _InteractionTrianglePainter extends CustomPainter {
  _InteractionTrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _InteractionTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
