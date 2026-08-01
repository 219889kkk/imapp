class MomentMediaType {
  static const text = 'text';
  static const image = 'image';
  static const video = 'video';
  static const voice = 'voice';
  static const file = 'file';
}

class MomentVisibility {
  static const public = 'public';
  static const friends = 'friends';
  static const private = 'private';
  static const partial = 'partial';
  static const exclude = 'exclude';
}

class MomentNotificationType {
  static const like = 'like';
  static const comment = 'comment';
  static const reply = 'reply';
}

class MomentProfile {
  MomentProfile({
    required this.userID,
    this.coverUrl,
    this.updatedAt = 0,
  });

  factory MomentProfile.fromJson(Map<String, dynamic> json) => MomentProfile(
        userID: json['userID'] ?? '',
        coverUrl: json['coverUrl'],
        updatedAt: json['updatedAt'] ?? 0,
      );

  final String userID;
  final String? coverUrl;
  final int updatedAt;
}

class MomentAuthor {
  MomentAuthor({
    required this.userID,
    required this.nickname,
    this.faceURL,
  });

  factory MomentAuthor.fromJson(Map<String, dynamic> json) => MomentAuthor(
        userID: json['userID'] ?? '',
        nickname: json['nickname'] ?? '',
        faceURL: json['faceURL'],
      );

  final String userID;
  final String nickname;
  final String? faceURL;

  Map<String, dynamic> toJson() => {
        'userID': userID,
        'nickname': nickname,
        'faceURL': faceURL,
      };
}

class MomentMedia {
  MomentMedia({
    required this.id,
    required this.type,
    required this.url,
    this.thumbUrl,
    this.name,
    this.size,
    this.duration,
    this.width,
    this.height,
  });

  factory MomentMedia.fromJson(Map<String, dynamic> json) => MomentMedia(
        id: json['id'] ?? '',
        type: json['type'] ?? MomentMediaType.image,
        url: json['url'] ?? '',
        thumbUrl: json['thumbUrl'],
        name: json['name'],
        size: json['size'],
        duration: json['duration'],
        width: json['width'],
        height: json['height'],
      );

  final String id;
  final String type;
  final String url;
  final String? thumbUrl;
  final String? name;
  final int? size;
  final int? duration;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'url': url,
        'thumbUrl': thumbUrl,
        'name': name,
        'size': size,
        'duration': duration,
        'width': width,
        'height': height,
      };
}

class MomentComment {
  MomentComment({
    required this.commentID,
    required this.postID,
    required this.userID,
    required this.nickname,
    required this.content,
    required this.createdAt,
    this.faceURL,
    this.replyToUserID,
    this.replyToNickname,
  });

  factory MomentComment.fromJson(Map<String, dynamic> json) => MomentComment(
        commentID: json['commentID'] ?? '',
        postID: json['postID'] ?? '',
        userID: json['userID'] ?? '',
        nickname: json['nickname'] ?? '',
        content: json['content'] ?? '',
        createdAt: json['createdAt'] ?? 0,
        faceURL: json['faceURL'],
        replyToUserID: json['replyToUserID'],
        replyToNickname: json['replyToNickname'],
      );

  final String commentID;
  final String postID;
  final String userID;
  final String nickname;
  final String content;
  final int createdAt;
  final String? faceURL;
  final String? replyToUserID;
  final String? replyToNickname;
}

class MomentPost {
  MomentPost({
    required this.postID,
    required this.author,
    required this.content,
    required this.mediaType,
    required this.mediaList,
    required this.visibility,
    required this.likeUsers,
    required this.comments,
    required this.createdAt,
    required this.updatedAt,
    this.allowUserIDs,
    this.excludeUserIDs,
    this.deletedAt,
    this.isLiked = false,
  });

  factory MomentPost.fromJson(Map<String, dynamic> json) => MomentPost(
        postID: json['postID'] ?? '',
        author: MomentAuthor.fromJson(json['author'] ?? {}),
        content: json['content'] ?? '',
        mediaType: json['mediaType'] ?? MomentMediaType.text,
        mediaList: _toList(json['mediaList'], MomentMedia.fromJson),
        visibility: json['visibility'] ?? MomentVisibility.friends,
        likeUsers: _toList(json['likeUsers'], MomentAuthor.fromJson),
        comments: _toList(json['comments'], MomentComment.fromJson),
        createdAt: json['createdAt'] ?? 0,
        updatedAt: json['updatedAt'] ?? 0,
        allowUserIDs: _toStringList(json['allowUserIDs']),
        excludeUserIDs: _toStringList(json['excludeUserIDs']),
        deletedAt: json['deletedAt'],
        isLiked: json['isLiked'] == true,
      );

  final String postID;
  final MomentAuthor author;
  final String content;
  final String mediaType;
  final List<MomentMedia> mediaList;
  final String visibility;
  final List<MomentAuthor> likeUsers;
  final List<MomentComment> comments;
  final int createdAt;
  final int updatedAt;
  final List<String>? allowUserIDs;
  final List<String>? excludeUserIDs;
  final int? deletedAt;
  bool isLiked;
}

class MomentFeedResp {
  MomentFeedResp({
    required this.list,
    required this.hasMore,
    this.cursor,
  });

  factory MomentFeedResp.fromJson(Map<String, dynamic> json) => MomentFeedResp(
        list: _toList(json['list'], MomentPost.fromJson),
        cursor: json['cursor']?.toString(),
        hasMore: json['hasMore'] == true,
      );

  final List<MomentPost> list;
  final String? cursor;
  final bool hasMore;
}

class MomentNotification {
  MomentNotification({
    required this.notificationID,
    required this.type,
    required this.postID,
    required this.receiverUserID,
    required this.operator,
    required this.isRead,
    required this.createdAt,
    this.content,
  });

  factory MomentNotification.fromJson(Map<String, dynamic> json) =>
      MomentNotification(
        notificationID: json['notificationID'] ?? '',
        type: json['type'] ?? '',
        postID: json['postID'] ?? '',
        receiverUserID: json['receiverUserID'] ?? '',
        operator: MomentAuthor.fromJson(json['operator'] ?? {}),
        content: json['content'],
        isRead: json['isRead'] == true,
        createdAt: json['createdAt'] ?? 0,
      );

  final String notificationID;
  final String type;
  final String postID;
  final String receiverUserID;
  final MomentAuthor operator;
  final String? content;
  final bool isRead;
  final int createdAt;
}

class MomentNotificationResp {
  MomentNotificationResp({
    required this.list,
    required this.hasMore,
    this.cursor,
  });

  factory MomentNotificationResp.fromJson(Map<String, dynamic> json) =>
      MomentNotificationResp(
        list: _toList(json['list'], MomentNotification.fromJson),
        cursor: json['cursor']?.toString(),
        hasMore: json['hasMore'] == true,
      );

  final List<MomentNotification> list;
  final String? cursor;
  final bool hasMore;
}

List<T> _toList<T>(dynamic value, T Function(Map<String, dynamic>) convert) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((e) => convert(Map<String, dynamic>.from(e)))
      .toList();
}

List<String>? _toStringList(dynamic value) {
  if (value is! List) return null;
  return value.map((e) => e.toString()).toList();
}
