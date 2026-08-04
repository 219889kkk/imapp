# iOS CallKit / VoIP（客户端约定）

> 服务端权威文档：`/opt/openim/chat/docs/VOIP_CALLKIT.md`  
> Bundle ID：`top.hangxun.app` · VoIP topic：`top.hangxun.app.voip`

## 分工

| 通道 | 用途 |
|------|------|
| 个推 + 普通 APNs | 文本/图片等聊天消息 |
| PushKit VoIP + CallKit | 语音/视频来电（杀进程/锁屏系统来电页） |

## 客户端必做

1. **个推**：登录 `bindAlias(userID)`；PushKit 拿到 VoIP Token 后原生调用 `GeTuiSdk.registerTokenCredentials`（见 `HangXunGetuiVoip.m`）。
2. **上报 Token**：登录后 / Token 刷新时 `POST /user/rtc/voip_token`，把真实 PushKit Token 存到被叫 userID（库里不能是 `bbbbbb...` 假值）。
3. **PushKit 收包**：在 `completion` 返回前调用 CallKit `reportNewIncomingCall`（`flutter_callkit_incoming` `showCallkitIncoming(..., fromPushKit: true)`）。
4. **主叫**：发送 `callingInvite`（customType `200`）后立即 `POST /user/rtc/voip_push`。

## `POST /user/rtc/voip_token`

被叫登录后上报（需 chat token）：

```json
{
  "userID": "6651546301",
  "voipToken": "<PushKit hex token>",
  "platformID": 1
}
```

## `POST /user/rtc/voip_push`

Base：`https://im.zghtchat9.top/chat`（与 `get_token` 同组，需 chat token）

```json
{
  "action": "invite",
  "inviteeUserIDList": ["calleeUserID"],
  "roomID": "uuid-room-id",
  "inviterUserID": "callerUserID",
  "mediaType": "audio",
  "nickname": "主叫昵称",
  "sessionType": 1,
  "groupID": "",
  "timeout": 60
}
```

- `action`: `invite` | `cancel` | `end` | `hungup`
- 服务端应对 `inviteeUserIDList` 发 **APNs VoIP**（`apns-topic: top.hangxun.app.voip`，`apns-push-type: voip`，`priority: 10`），payload 字段与上表一致，便于被叫 CallKit 展示与接听。

## 苹果证书（运维）

1. App ID `top.hangxun.app` 开启 Push Notifications。
2. 申请 **VoIP Services Certificate**，导出 `.p12`（或 AuthKey `.p8` + topic `.voip`）。
3. 上传到 OpenIM / 自建 VoIP 发送逻辑（**不要**指望个推普通消息弹 CallKit）。
4. Debug：`Runner.entitlements` → `aps-environment=development`；TestFlight/正式 → `production`。

## 真机验收

1. 登录后日志可见 VoIP token + `registerVoipTokenCredentials`。
2. 被叫划掉 App → 主叫语音/视频 → **系统来电页**（非普通通知）。
3. 接听进入 LiveKit；取消/拒绝后 CallKit 消失。
4. 普通文本仍走个推横幅。
