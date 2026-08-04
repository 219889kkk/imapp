# VoIP / CallKit 交接说明（客户端 → 服务端）

> 给服务端同学：用 **Cursor**（或同类 Agent）打开仓库后，把本文贴进新对话即可接替联调。  
> 客户端权威约定补充见 [VOIP_CALLKIT.md](./VOIP_CALLKIT.md)；服务端权威文档：`/opt/openim/chat/docs/VOIP_CALLKIT.md`。

---

## 1. 链接与权限

### 仓库 / 构建

| 用途 | 链接 | 需要的权限 |
|------|------|------------|
| 客户端 GitHub | https://github.com/219889kkk/imapp | **Read**（看代码/PR）；建议 **Write**（若要改客户端或触发 Actions） |
| Clone | `git clone https://github.com/219889kkk/imapp.git` | 同上 |
| 分支 | `master`（当前联调基线） | — |
| Actions 构建 | https://github.com/219889kkk/imapp/actions | **Read** Artifacts；触发 workflow 需 **Write** 或维护者权限 |
| 含完整 JSON Toast 的包 | https://github.com/219889kkk/imapp/actions/runs/30939667533 （commit `567c373`） | 下载 `openim-ios-unsigned` / Android Artifact |
| 签名 IPA 工作流 | Actions → **iOS Signed**（需先配 Secrets，见下） | Secrets 维护者 + Actions |

### 线上服务

| 用途 | 地址 / 路径 | 需要的权限 |
|------|-------------|------------|
| Chat API Base | `https://im.zghtchat9.top/chat` | 能打接口 / 看网关或应用日志 |
| VoIP Token 上报 | `POST /user/rtc/voip_token` | 服务端代码 + 库读写 |
| VoIP 推送 | `POST /user/rtc/voip_push` | 同上 + APNs VoIP 证书 |
| 服务端文档 | `/opt/openim/chat/docs/VOIP_CALLKIT.md` | 服务器 SSH 或对应 git 仓库读权限 |
| 服务端代码（请补全你们真实仓库 URL） | 部署机 `/opt/openim/chat` 或内部 git | **Clone + 改 voip_token 落库逻辑** |

### Apple / 推送（运维）

| 用途 | 说明 | 权限 |
|------|------|------|
| Bundle ID | `top.hangxun.app` | Apple Developer 团队访问 |
| VoIP topic | `top.hangxun.app.voip` | VoIP Services 证书 / AuthKey |
| 个推 | 普通消息仍走个推；杀进程系统来电走 **APNs VoIP**，不要指望普通通知弹 CallKit | 个推控制台（消息）+ 自建 VoIP 发推 |

### GitHub Secrets（仅 CI 签名需要，与 VoIP 推送证书无关）

| Secret | 含义 |
|--------|------|
| `IOS_P12_BASE64` | **代码签名** `.p12`（不要用 VoIP 推送 p12） |
| `IOS_P12_PASSWORD` | p12 密码 |
| `IOS_PROFILE_APP_BASE64` | `top.hangxun.app` 描述文件 |
| `IOS_PROFILE_NSE_BASE64` | `top.hangxun.app.NotificationService` 描述文件 |
| `IOS_TEAM_ID` | 默认工程内为 `U7QZA36QT4` |
| `IOS_KEYCHAIN_PASSWORD` | CI 临时钥匙串（可选） |

本地上传脚本：`scripts/prepare-ios-signing-secrets.ps1`（加 `-Apply` 写入 Secrets）。

### Cursor 怎么接替

1. 安装 [Cursor](https://cursor.com)，用有仓库权限的 GitHub 账号登录。  
2. **Clone 客户端** `imapp`；若有服务端 git，**一并打开**（多根目录 Workspace 最佳）。  
3. 新 Agent 对话粘贴：  
   > 请阅读 `docs/HANDOFF_VOIP.md` 与 `docs/VOIP_CALLKIT.md`，继续排查 `voip_token` 不落库问题。  
4. （可选）向管理员要本机 Cursor 对话摘要：联调会话 ID `bba15d5d-faf7-48ef-9609-6d9f360c0292`。

**权限清单（给人开账号时勾选）**

- [ ] GitHub `219889kkk/imapp`：Read（必）/ Write（建议）/ Actions Artifacts  
- [ ] 服务端 chat 仓库或 `/opt/openim/chat`：读代码 + 改 `voip_token`  
- [ ] MySQL/库：查用户 VoIP Token（至少 `6651546301`）  
- [ ] 应用/网关日志：能看到 `/user/rtc/voip_token` 请求与响应体  
- [ ] （可选）Apple Developer、VoIP 证书、真机 UDID / Ad Hoc 描述文件  

---

## 2. 当前现象（截至交接）

| 项 | 状态 |
|----|------|
| 账号 test0099 | userID **`6651546301`** |
| 库里 VoIP Token | 仍是假值 **全 `b`（bbbbbb…）** |
| 库更新时间 | 停在 **`08-04 15:51`**（之后多次上报未落库） |
| 客户端请求 | 已多次 `POST /user/rtc/voip_token` |
| 响应体大小 | 失败约 **63 字节**；成功写入约 **124 字节** → 现网一直是失败响应 |
| 主叫 voip_push | 有请求；无真实 Token 时 APNs 打不到真机 |

---

## 3. 接口约定（客户端已按此实现）

### `POST /user/rtc/voip_token`

- Base：`https://im.zghtchat9.top/chat`  
- Header：`token` = **chat 登录 token**（不是 PushKit）；`operationID` = 毫秒时间戳  
- Body（字段名必须是 **`token`**）：

```json
{
  "userID": "6651546301",
  "token": "<PushKit hex，非空，非全 b/0/f>",
  "platformID": 1
}
```

- 成功：`errCode=0`，库中该 userID 的 VoIP Token 更新为 hex。  
- 请在服务端日志打印并返回清晰的 **`errCode` / `errMsg` / `errDlt`**（客户端会 Toast + `[VOIP_TOKEN]` 打印完整 JSON）。

### `POST /user/rtc/voip_push`

主叫 `callingInvite`（customType `200`）后调用；对 `inviteeUserIDList` 发 **APNs VoIP**（topic `top.hangxun.app.voip`）。详见 [VOIP_CALLKIT.md](./VOIP_CALLKIT.md)。

---

## 4. 客户端已完成（关键 commits）

| Commit | 内容 |
|--------|------|
| `36afe14` | 登录后上报真实 PushKit Token |
| `17f2820` | PushKit 早于 Flutter 插件时仍写入 UserDefaults，避免 Token 丢失 |
| `0c04f8d` | Body 字段改为 **`token`**；打 errCode/errDlt |
| `567c373` | **完整响应 JSON** + 屏幕 Toast（Release 也能看见） |
| `f2a7a76` | CI：iOS Signed 工作流（需 Secrets） |

关键文件：

- `openim_common/lib/src/apis.dart` → `Apis.updateVoipToken`  
- `openim_common/lib/src/controller/voip_callkit_controller.dart`  
- `openim_common/lib/src/urls.dart` → `Urls.voipToken`  
- `ios/Runner/AppDelegate.swift` → PushKit / CallKit / Token 落盘  

---

## 5. 服务端请优先排查

1. 对一次真实失败请求看完整 JSON：`errCode`、`errDlt`（常见：`token is empty`、鉴权失败、ArgsError）。  
2. Handler 是否读 **body.`token`**（若仍读 `voipToken`，会一直判空 → ~63 字节失败）。  
3. 鉴权 header `token`（chat）与 body `token`（PushKit）是否被中间件搞混。  
4. 写入成功后是否覆盖假 Token；假值 `bbbbbb…` 的初始写入来源。  
5. `platformID` / userID 校验是否误拒。  

验收：test0099 真机装 **`567c373` 及以后** 的包 → 登录后 Toast 为 `voip_token ok` 或把失败 JSON 贴回 → 库中 `6651546301` 变为真实 hex → 再测 test0077→test0099 杀进程 CallKit。

---

## 6. 测试账号

| 角色 | 账号 | userID | 备注 |
|------|------|--------|------|
| 被叫 | test0099 | `6651546301` | 必须真机；库 Token 需真实 |
| 主叫 | test0077 | `8650061551` | 主叫侧调 voip_push |

---

## 7. 给 Cursor Agent 的一句话 Prompt

```text
阅读 docs/HANDOFF_VOIP.md 与 docs/VOIP_CALLKIT.md。
线上 POST /user/rtc/voip_token 多次失败（响应约 63 字节），库里 6651546301 仍是全 b 假 Token。
客户端 body 字段是 token（PushKit hex），header token 是 chat 鉴权。
请在服务端定位 voip_token 不落库原因（字段名/鉴权/校验），修好并说明如何用 test0099 验收。
```
