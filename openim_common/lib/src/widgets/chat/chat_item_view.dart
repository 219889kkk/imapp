import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_detector_v2/focus_detector_v2.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';

import 'chat_notice_view.dart';

double maxWidth = 247.w;
double pictureWidth = 120.w;
double videoWidth = 120.w;
double locationWidth = 220.w;

BorderRadius borderRadius(bool isISend) => BorderRadius.only(
      topLeft: Radius.circular(isISend ? 6.r : 0),
      topRight: Radius.circular(isISend ? 0 : 6.r),
      bottomLeft: Radius.circular(6.r),
      bottomRight: Radius.circular(6.r),
    );

class MsgStreamEv<T> {
  final String id;
  final T value;

  MsgStreamEv({required this.id, required this.value});

  @override
  String toString() {
    return 'MsgStreamEv{msgId: $id, value: $value}';
  }
}

class CustomTypeInfo {
  final Widget customView;
  final bool needBubbleBackground;
  final bool needChatItemContainer;

  CustomTypeInfo(
    this.customView, [
    this.needBubbleBackground = true,
    this.needChatItemContainer = true,
  ]);
}

typedef CustomTypeBuilder = CustomTypeInfo? Function(
  BuildContext context,
  Message message,
);
typedef NotificationTypeBuilder = Widget? Function(
  BuildContext context,
  Message message,
);
typedef ItemViewBuilder = Widget? Function(
  BuildContext context,
  Message message,
);
typedef ItemVisibilityChange = void Function(
  Message message,
  bool visible,
);

class ChatItemView extends StatefulWidget {
  const ChatItemView({
    Key? key,
    this.mediaItemBuilder,
    this.itemViewBuilder,
    this.customTypeBuilder,
    this.notificationTypeBuilder,
    this.sendStatusSubject,
    this.visibilityChange,
    this.timelineStr,
    this.leftNickname,
    this.leftFaceUrl,
    this.rightNickname,
    this.rightFaceUrl,
    required this.message,
    this.textScaleFactor = 1.0,
    this.ignorePointer = false,
    this.showLeftNickname = true,
    this.showRightNickname = false,
    this.highlightColor,
    this.allAtMap = const {},
    this.patterns = const [],
    this.onTapLeftAvatar,
    this.onTapRightAvatar,
    this.onLongPressRightAvatar,
    this.onVisibleTrulyText,
    this.onFailedToResend,
    this.onClickItemView,
    this.onTapReadTag,
    this.onTapMergeMessage,
    this.showReadTag = true,
    required this.onTapUserProfile,
  }) : super(key: key);
  final ItemViewBuilder? mediaItemBuilder;
  final ItemViewBuilder? itemViewBuilder;
  final CustomTypeBuilder? customTypeBuilder;
  final NotificationTypeBuilder? notificationTypeBuilder;

  final Subject<MsgStreamEv<bool>>? sendStatusSubject;

  final ItemVisibilityChange? visibilityChange;
  final String? timelineStr;
  final String? leftNickname;
  final String? leftFaceUrl;
  final String? rightNickname;
  final String? rightFaceUrl;
  final Message message;

  final double textScaleFactor;
  final bool ignorePointer;
  final bool showLeftNickname;
  final bool showRightNickname;

  final Color? highlightColor;
  final Map<String, String> allAtMap;
  final List<MatchPattern> patterns;
  final Function()? onTapLeftAvatar;
  final Function()? onTapRightAvatar;
  final Function()? onLongPressRightAvatar;
  final Function(String? text)? onVisibleTrulyText;
  final Function()? onClickItemView;
  final ValueChanged<Message>? onTapMergeMessage;
  final ValueChanged<
          ({String userID, String name, String? faceURL, String? groupID})>
      onTapUserProfile;

  final Function()? onFailedToResend;
  final Function()? onTapReadTag;
  final bool showReadTag;
  @override
  State<ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<ChatItemView> {
  final _voicePlayer = AudioPlayer();
  String? _playingVoiceID;

  Message get _message => widget.message;

  bool get _isISend => _message.sendID == OpenIM.iMManager.userID;

  TextStyle get _bubblePrimaryTextStyle =>
      _isISend ? Styles.ts_bubbleSentText_14sp : Styles.ts_0C1C33_14sp;

  TextStyle get _bubblePrimaryTitleStyle =>
      _isISend ? Styles.ts_bubbleSentText_17sp : Styles.ts_0C1C33_17sp;

  TextStyle get _bubbleSecondaryTextStyle => _isISend
      ? Styles.ts_bubbleSentText_14sp.copyWith(
          fontSize: 12.sp,
          color: Styles.bubbleSentText.withValues(alpha: 0.72),
        )
      : Styles.ts_8E9AB0_12sp;

  Color get _bubbleDividerColor => _isISend
      ? Styles.bubbleSentText.withValues(alpha: 0.24)
      : Styles.c_E8EAEF;

  @override
  void dispose() {
    _voicePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusDetector(
      child: Container(
        color: widget.highlightColor,
        margin: EdgeInsets.only(bottom: 20.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        child: Center(child: _child),
      ),
      onVisibilityLost: () {
        widget.visibilityChange?.call(widget.message, false);
      },
      onVisibilityGained: () {
        widget.visibilityChange?.call(widget.message, true);
      },
    );
  }

  Widget get _child =>
      widget.itemViewBuilder?.call(context, _message) ?? _buildChildView();

  Widget _buildChildView() {
    Widget? child;
    String? senderNickname;
    String? senderFaceURL;
    bool isBubbleBg = false;

    if (_message.isCustomType) {
      if (_message.isCallingSignalingType) {
        return const SizedBox.shrink();
      }
      final customInfo = widget.customTypeBuilder?.call(context, _message);
      if (customInfo != null) {
        if (!customInfo.needChatItemContainer) {
          return customInfo.customView;
        }
        child = customInfo.customView;
        isBubbleBg = customInfo.needBubbleBackground;
      }
    } else if (_message.isTextType) {
      isBubbleBg = true;
      final text = _message.textElem?.content?.isNotEmpty == true
          ? _message.textElem!.content!
          : (_message.localEx ?? '');
      child = ChatText(
        isISend: _isISend,
        text: text,
        patterns: _patternsFor(_message),
        textScaleFactor: widget.textScaleFactor,
        onVisibleTrulyText: widget.onVisibleTrulyText,
      );
    } else if (_message.contentType == MessageType.atText) {
      isBubbleBg = true;
      child = ChatText(
        isISend: _isISend,
        text: _message.atTextElem?.text ?? '',
        patterns: _patternsFor(_message),
        textScaleFactor: widget.textScaleFactor,
        onVisibleTrulyText: widget.onVisibleTrulyText,
      );
    } else if (_message.contentType == MessageType.quote) {
      isBubbleBg = true;
      child = _buildQuoteView(_message);
    } else if (_message.isPictureType) {
      child = widget.mediaItemBuilder?.call(context, _message) ??
          ChatPictureView(
            isISend: _isISend,
            message: _message,
          );
    } else if (_message.isVideoType) {
      child = _buildVideoView(_message);
    } else if (_message.isVoiceType) {
      isBubbleBg = true;
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _playVoice(_message),
        child: _buildVoiceView(_message),
      );
    } else if (_message.isFileType) {
      isBubbleBg = true;
      child = _buildFileView(_message);
    } else if (_message.isMergerType) {
      isBubbleBg = true;
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTapMergeMessage?.call(_message),
        child: _buildMergeView(_message),
      );
    } else if (_message.isCardType) {
      isBubbleBg = true;
      child = _buildCardView(_message);
    } else if (_message.isLocationType) {
      isBubbleBg = true;
      child = _buildLocationView(_message);
    } else if (_message.isNotificationType) {
      if (_message.contentType ==
          MessageType.groupInfoSetAnnouncementNotification) {
        final map = json.decode(_message.notificationElem!.detail!);
        final ntf = GroupNotification.fromJson(map);
        final noticeContent = ntf.group?.notification;
        senderNickname = ntf.opUser?.nickname;
        senderFaceURL = ntf.opUser?.faceURL;
        child = ChatNoticeView(isISend: _isISend, content: noticeContent!);
      } else {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ChatHintTextView(
            message: _message,
            onTapUserProfile: widget.onTapUserProfile,
          ),
        );
      }
    }

    senderNickname ??= widget.leftNickname ?? _message.senderNickname;
    senderFaceURL ??= widget.leftFaceUrl ?? _message.senderFaceUrl;
    return child = ChatItemContainer(
      id: _message.clientMsgID!,
      isISend: _isISend,
      leftNickname: senderNickname,
      leftFaceUrl: senderFaceURL,
      rightNickname: widget.rightNickname ?? OpenIM.iMManager.userInfo.nickname,
      rightFaceUrl: widget.rightFaceUrl ?? OpenIM.iMManager.userInfo.faceURL,
      showLeftNickname: widget.showLeftNickname,
      showRightNickname: widget.showRightNickname,
      timelineStr: widget.timelineStr,
      hasRead: _message.isRead!,
      isSending: _message.isVideoType
          ? false
          : _message.status == MessageStatus.sending,
      isSendFailed: _message.status == MessageStatus.failed,
      isBubbleBg: child == null ? true : isBubbleBg,
      readTag: _buildReadTag(),
      ignorePointer: widget.ignorePointer,
      sendStatusStream: widget.sendStatusSubject,
      onFailedToResend: widget.onFailedToResend,
      onLongPressRightAvatar: widget.onLongPressRightAvatar,
      onTapLeftAvatar: widget.onTapLeftAvatar,
      onTapRightAvatar: widget.onTapRightAvatar,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onClickItemView,
        child: child ?? ChatText(text: StrRes.unsupportedMessage),
      ),
    );
  }

  bool _isCallRecordMessage() {
    final data = IMUtils.parseCustomMessage(_message);
    return data != null && data['viewType'] == CustomMessageType.call;
  }

  Widget? _buildReadTag() {
    if (!widget.showReadTag ||
        !_isISend ||
        _message.status != MessageStatus.succeeded ||
        _message.isNotificationType ||
        _message.contentType == MessageType.typing ||
        _isCallRecordMessage()) {
      return null;
    }
    return ChatReadTagView(message: _message, onTap: widget.onTapReadTag);
  }

  List<MatchPattern> _patternsFor(Message message) {
    final patterns = [...widget.patterns];
    if (message.contentType == MessageType.atText) {
      for (final nickname in widget.allAtMap.values) {
        patterns.add(MatchPattern(
          type: PatternType.custom,
          pattern: RegExp.escape('@$nickname'),
          style: Styles.ts_0089FF_17sp,
        ));
      }
    }
    return patterns;
  }

  Widget _buildVoiceView(Message message) {
    final duration = message.soundElem?.duration ?? 0;
    final width = (72 + duration * 3).clamp(88, 180).toDouble().w;
    final isPlaying = _playingVoiceID == message.clientMsgID;
    final icon = _isISend
        ? (Styles.isDark ? ImageRes.voiceWhite : ImageRes.voiceBlack)
        : ImageRes.voiceBlue;
    final style =
        _isISend ? Styles.ts_bubbleSentText_14sp : Styles.ts_0C1C33_14sp;
    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment:
            _isISend ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!_isISend)
            icon.toImage
              ..width = 20.w
              ..height = 20.h,
          if (!_isISend) 8.horizontalSpace,
          '${duration == 0 ? 1 : duration}"'.toText..style = style,
          if (isPlaying) 6.horizontalSpace,
          if (isPlaying)
            SizedBox(
              width: 10.w,
              height: 10.h,
              child: CircularProgressIndicator(
                strokeWidth: 1.5.w,
                color: _isISend ? Styles.bubbleSentText : Styles.c_0089FF,
              ),
            ),
          if (_isISend) 8.horizontalSpace,
          if (_isISend)
            icon.toImage
              ..width = 20.w
              ..height = 20.h,
        ],
      ),
    );
  }

  Future<void> _playVoice(Message message) async {
    final sound = message.soundElem;
    if (sound == null) return;
    try {
      setState(() => _playingVoiceID = message.clientMsgID);
      await _voicePlayer.stop();
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      ));
      await session.setActive(true);
      final path = await IMUtils.resolveVoicePlayPath(
        soundPath: sound.soundPath,
        sourceUrl: sound.sourceUrl,
        cacheKey: sound.uuid ?? message.clientMsgID,
      );
      if (path == null) {
        Logger.print(
          '_playVoice resolve path failed: '
          'clientMsgID=${message.clientMsgID}, '
          'soundPath=${sound.soundPath}, '
          'sourceUrl=${sound.sourceUrl}, '
          'cacheKey=${sound.uuid ?? message.clientMsgID}',
        );
        _showVoicePlayError('resolve voice path failed');
        return;
      }
      await _voicePlayer.setFilePath(path);
      await _voicePlayer.play();
    } catch (e, s) {
      Logger.print(
        '_playVoice error: '
        'clientMsgID=${message.clientMsgID}, '
        'soundPath=${sound.soundPath}, '
        'sourceUrl=${sound.sourceUrl}, '
        'cacheKey=${sound.uuid ?? message.clientMsgID}, '
        'error=$e $s',
      );
      _showVoicePlayError('$e');
    } finally {
      if (mounted) {
        setState(() => _playingVoiceID = null);
      }
    }
  }

  void _showVoicePlayError(String detail) {
    final message = '${StrRes.networkError} ($detail)';
    IMViews.showToast(
      message.length > 120 ? message.substring(0, 120) : message,
    );
  }

  Widget _buildCardView(Message message) {
    final card = message.cardElem;
    final name = card?.nickname ?? '';
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 190.w, maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AvatarView(
                url: card?.faceURL,
                text: name,
                width: 42.w,
                height: 42.h,
              ),
              10.horizontalSpace,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    name.toText
                      ..style = _bubblePrimaryTextStyle
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis,
                    4.verticalSpace,
                    (card?.userID ?? '').toText
                      ..style = _bubbleSecondaryTextStyle
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis,
                  ],
                ),
              ),
            ],
          ),
          8.verticalSpace,
          Container(height: 1, color: _bubbleDividerColor),
          6.verticalSpace,
          StrRes.carte.toText..style = _bubbleSecondaryTextStyle,
        ],
      ),
    );
  }

  Widget _buildLocationView(Message message) {
    final location = message.locationElem;
    final description = location?.description ?? StrRes.location;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Get.to(() => MapView(
              latitude: location?.latitude ?? 0,
              longitude: location?.longitude ?? 0,
              address1: description,
              address2:
                  '${location?.latitude ?? 0}, ${location?.longitude ?? 0}',
            ));
      },
      child: Container(
        width: 220.w,
        padding: EdgeInsets.all(10.w),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              color: Styles.c_FF381F,
              size: 28.w,
            ),
            8.horizontalSpace,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  description.toText
                    ..style = Styles.ts_0C1C33_17sp
                    ..maxLines = 2
                    ..overflow = TextOverflow.ellipsis,
                  4.verticalSpace,
                  StrRes.location.toText..style = Styles.ts_8E9AB0_12sp,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoView(Message message) {
    final video = message.videoElem;
    final snapshotPath = video?.snapshotPath;
    final snapshotUrl = video?.snapshotUrl?.adjustThumbnailAbsoluteString(960);
    Widget snapshot;
    if (IMUtils.isNotNullEmptyStr(snapshotPath) &&
        File(snapshotPath!).existsSync()) {
      snapshot = ImageUtil.fileImage(
        file: File(snapshotPath),
        width: videoWidth,
        height: videoWidth,
        fit: BoxFit.cover,
      );
    } else if (IMUtils.isNotNullEmptyStr(snapshotUrl)) {
      snapshot = ImageUtil.networkImage(
        url: snapshotUrl!,
        width: videoWidth,
        height: videoWidth,
        fit: BoxFit.cover,
      );
    } else {
      snapshot = Container(
        width: videoWidth,
        height: videoWidth,
        color: Styles.c_E8EAEF,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius(_isISend),
      child: SizedBox(
        width: videoWidth,
        height: videoWidth,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: snapshot),
            Positioned.fill(
              child: Container(color: Styles.c_000000.withValues(alpha: .18)),
            ),
            ImageRes.progressPlay.toImage
              ..width = 36.w
              ..height = 36.h,
            Positioned(
              right: 6.w,
              bottom: 4.h,
              child: _formatVideoDuration(video?.duration).toText
                ..style = Styles.ts_FFFFFF_12sp,
            ),
          ],
        ),
      ),
    );
  }

  String _formatVideoDuration(int? seconds) {
    final value = seconds ?? 0;
    final minutes = value ~/ 60;
    final remain = value % 60;
    return '$minutes:${remain.toString().padLeft(2, '0')}';
  }

  Widget _buildFileView(Message message) {
    final fileElem = message.fileElem;
    final fileName = fileElem?.fileName ?? StrRes.file;
    final fileSize = fileElem?.fileSize;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 190.w, maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IMUtils.fileIcon(fileName).toImage
            ..width = 40.w
            ..height = 40.h,
          10.horizontalSpace,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                fileName.toText
                  ..style = _bubblePrimaryTextStyle
                  ..maxLines = 2
                  ..overflow = TextOverflow.ellipsis,
                if (fileSize != null) 4.verticalSpace,
                if (fileSize != null)
                  IMUtils.formatBytes(fileSize).toText
                    ..style = _bubbleSecondaryTextStyle,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMergeView(Message message) {
    final merge = message.mergeElem;
    final title = IMUtils.isNotNullEmptyStr(merge?.title)
        ? merge!.title!
        : StrRes.chatRecord;
    final abstracts = merge?.abstractList ?? const <String>[];
    final summaries =
        abstracts.isEmpty ? <String>[StrRes.mergeForward] : abstracts;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 190.w, maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title.toText
            ..style = _bubblePrimaryTitleStyle
            ..maxLines = 1
            ..overflow = TextOverflow.ellipsis,
          8.verticalSpace,
          ...summaries.take(4).map(
                (summary) => Padding(
                  padding: EdgeInsets.only(bottom: 4.h),
                  child: summary.toText
                    ..style = _bubbleSecondaryTextStyle
                    ..maxLines = 1
                    ..overflow = TextOverflow.ellipsis,
                ),
              ),
          4.verticalSpace,
          Container(height: 1, color: _bubbleDividerColor),
          6.verticalSpace,
          StrRes.chatRecord.toText..style = _bubbleSecondaryTextStyle,
        ],
      ),
    );
  }

  Widget _buildQuoteView(Message message) {
    final quoted = message.quoteElem?.quoteMessage;
    final quotedSender = quoted?.senderNickname;
    final quotedContent = quoted == null
        ? StrRes.quoteContentBeRevoked
        : IMUtils.parseMsg(quoted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChatText(
          isISend: _isISend,
          text: message.quoteElem?.text ?? '',
          patterns: widget.patterns,
          textScaleFactor: widget.textScaleFactor,
          onVisibleTrulyText: widget.onVisibleTrulyText,
        ),
        6.verticalSpace,
        Container(
          constraints: BoxConstraints(maxWidth: maxWidth - 40.w),
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: Styles.insetBackground,
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Text(
            quotedSender == null
                ? quotedContent
                : '$quotedSender: $quotedContent',
            style: Styles.ts_8E9AB0_14sp,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
