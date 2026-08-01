class AgentInfo {
  AgentInfo({
    required this.userID,
    required this.nickname,
    this.faceURL,
    this.url,
    this.identity,
    this.model,
    this.prompts,
    this.createTime,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        userID: json['userID'] ?? '',
        nickname: json['nickname'] ?? '',
        faceURL: json['faceURL'],
        url: json['url'],
        identity: json['identity'],
        model: json['model'],
        prompts: json['prompts'],
        createTime: json['createTime'],
      );

  final String userID;
  final String nickname;
  final String? faceURL;
  final String? url;
  final String? identity;
  final String? model;
  final String? prompts;
  final int? createTime;
}

class AgentPageResp {
  AgentPageResp({
    required this.total,
    required this.agents,
  });

  factory AgentPageResp.fromJson(Map<String, dynamic> json) => AgentPageResp(
        total: json['total'] ?? 0,
        agents: (json['agents'] is List ? json['agents'] as List : [])
            .whereType<Map>()
            .map((e) => AgentInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  final int total;
  final List<AgentInfo> agents;
}
