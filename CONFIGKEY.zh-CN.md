
# 常见功能配置指南

- [离线推送功能](#离线推送功能)
- [地图功能](#地图功能)

## 离线推送功能

目前使用的是集成方案。客户端已接入 **iOS / Android 个推**（`getuiflut`）：登录后绑定 OpenIM `userID` 为别名；密钥非占位时自动启用 `PushType.getui`。

### 杀进程也能收推送的前提（缺一不可）

1. **个推控制台**已创建应用  
   - iOS Bundle ID：`top.hangxun.app`  
   - Android 包名：`io.openim.flutter.demo`
2. 客户端填入真实 **AppID / AppKey / AppSecret**（见下方；**Master Secret 仅给 OpenIM 服务端用，不要写进 App**）
3. **iOS**：个推后台已上传 Apple APNs 证书/密钥  
   **Android**：已配置 `GETUI_APPID`；小米/华为等机型建议再开通**厂商通道**（见下方）
4. **OpenIM 服务端**配置个推推送（AppID/AppKey/AppSecret/**Master Secret**，按 userID/别名下发）
5. iOS 正式签名勾选 Push Notifications；Android 13+ 允许通知权限，并尽量关闭电池优化限制

> 仅改客户端 SDK ≠ 离线可收。必须：个推密钥 +（iOS APNs / Android 厂商通道）+ OpenIM 服务端推送配置 齐全。

### 客户端配置

#### 1. 中国大陆地区使用个推（[Getui](https://getui.com/)）

###### 在[Getui](https://getui.com/)的集成指南，配置iOS和Android。

**iOS / 公共密钥：**
- **[push_controller.dart](openim_common/lib/src/controller/push_controller.dart)**

```dart
  const appID = 'your-app-id';
  const appKey = 'your-app-key';
  const appSecret = 'your-app-secret';
```

替换为真实值后，下次启动会自动 `pushType = getui`，登录时 `bindAlias(userID)`。

**Android 工程已改：**
- `android/app/build.gradle` → `GETUI_APPID` + 个推 SDK 依赖  
- 启动时 `initGetuiSdk` + `turnOnPush` + 申请通知权限  

**小米 / Redmi（如 Redmi 14C）必做厂商通道，否则杀进程很难唤醒：**
1. 在[小米开放平台](https://dev.mi.com/console)创建应用，包名与 `io.openim.flutter.demo` 一致，开通消息推送，拿到 AppID / AppKey  
2. 在个推控制台绑定小米厂商通道  
3. 填到 `android/app/build.gradle`：

```gradle
  XIAOMI_APP_ID  : "你的小米AppID",
  XIAOMI_APP_KEY : "你的小米AppKey",
```

4. 手机设置：允许通知、自启动、关闭电池优化（省电策略）

华为 / OPPO / vivo / 荣耀同理填对应占位符。

#### 2. 海外地区使用 [FCM（Firebase Cloud Messaging）](https://firebase.google.com/docs/cloud-messaging)

根据 [FCM](https://firebase.google.com/docs/cloud-messaging) 的集成指南，替换以下文件：

- **[google-services.json](android/app/google-services.json)**（Android 平台）
- **[GoogleService-Info.plist](ios/Runner/GoogleService-Info.plist)**（iOS 平台）
- **[firebase_options.dart](openim_common/lib/src/controller/firebase_options.dart)**（Dart 项目中的 Firebase 配置）

### 离线推送横幅设置

目前SDK的设计是直接由客户端控制推送横幅的展示内容。发送消息时，设置入参[offlinePushInfo](https://github.com/openimsdk/openim-flutter-demo/blob/cc72b6d7ca5f70ca07885857beecec512f904f8c/lib/pages/chat/chat_logic.dart#L543)：

```dart
  final offlinePushInfo = OfflinePushInfo(
    title: "填写标题",
    desc: "填写描述信息，例如消息内容",
    iOSBadgeCount: true,
  );
  // 如果不自定义offlinePushInfo，则title默认为app名称，desc默认为为“你收到了一条新消息”
```

根据实际需求，完成对应的客户端和服务端配置后即可启用离线推送功能。

---

## 地图功能

### 配置指南

需要配置对应的 AMap Key。具体请参考 [AMap 文档](https://lbs.amap.com/)，工程中的代码需要修改以下 Key：

- **[webKey](https://github.com/openimsdk/openim-flutter-demo/blob/5720a10a31a0a9bc5319775f9f4da83d6996dbfe/openim_common/lib/src/config.dart#L49)**
- **[webServerKey](https://github.com/openimsdk/openim-flutter-demo/blob/5720a10a31a0a9bc5319775f9f4da83d6996dbfe/openim_common/lib/src/config.dart#L50)**

```dart
  static const webKey = 'webKey';
  static const webServerKey = 'webServerKey';
```

完成配置后即可启用地图功能。
