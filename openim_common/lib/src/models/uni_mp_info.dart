import 'dart:convert';

class UniMPInfo {
  String? id;
  String? appID;
  String? name;
  String? icon;
  String? url;
  String? md5;
  int? size;
  String? version;
  int? priority;
  int? status;
  int? createTime;
  int? progress;

  UniMPInfo({
    this.id,
    this.appID,
    this.name,
    this.icon,
    this.url,
    this.md5,
    this.size,
    this.version,
    this.priority,
    this.status,
    this.createTime,
    this.progress,
  });

  UniMPInfo.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    appID = json['appID'];
    name = json['name'];
    icon = json['icon'];
    url = json['url'];
    md5 = json['md5'];
    size = json['size'];
    version = json['version'];
    priority = json['priority'];
    status = json['status'];
    createTime = json['createTime'];
    progress = json['progress'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['appID'] = appID;
    data['name'] = name;
    data['icon'] = icon;
    data['url'] = url;
    data['progress'] = progress;
    data['md5'] = md5;
    data['size'] = size;
    data['version'] = version;
    data['priority'] = priority;
    data['status'] = status;
    data['createTime'] = createTime;
    data['progress'] = progress;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}
