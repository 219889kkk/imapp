package io.openim;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.plugin.common.MethodChannel;
import io.openim.flutter_openim_sdk.connectivity.HangxunImKeepAlivePoke;

/**
 * Show an incoming-call UI from the IM websocket callback itself.
 * Dart/CallKit is often frozen after 1–3 minutes of lock even when the
 * socket is still up — this path does not wait for the isolate.
 */
public class HangxunIncomingCall {
    public static final String ACTION_RAW = "io.openim.hangxun.IM_RAW_MESSAGE";
    public static final String ACTION_ACCEPT = "io.openim.hangxun.CALL_ACCEPT";
    public static final String ACTION_REJECT = "io.openim.hangxun.CALL_REJECT";
    static final String EXTRA_ROOM = "roomID";
    static final String EXTRA_CALLER = "caller";
    static final String EXTRA_VIDEO = "video";
    static final String EXTRA_INVITER = "inviterUserID";
    static final String EXTRA_MEDIA = "mediaType";
    static final String EXTRA_TIMEOUT = "timeout";
    static final String EXTRA_JSON = "inviteJson";

    private static final String TAG = "HangxunIncomingCall";
    private static final String CHANNEL_ID = "hangxun_native_call";
    private static final int NOTIF_ID = 71010;

    private static MediaPlayer ringtone;
    private static String ringingRoomID;
    private static String ringingJson;

    private HangxunIncomingCall() {}

    public static void onRawMessage(Context context, String json) {
        if (context == null || json == null || json.isEmpty()) return;
        Context app = context.getApplicationContext();
        try {
            JSONObject msg = new JSONObject(json);
            JSONObject customElem = msg.optJSONObject("customElem");
            if (customElem == null) return;
            Object dataRaw = customElem.opt("data");
            if (dataRaw == null) return;
            JSONObject payload = dataRaw instanceof JSONObject
                    ? (JSONObject) dataRaw
                    : new JSONObject(String.valueOf(dataRaw));
            int customType = payload.optInt("customType", 0);
            JSONObject data = payload.optJSONObject("data");
            if (data == null) return;
            String roomID = data.optString("roomID", "");
            if (roomID.isEmpty()) return;

            String self = app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                    .getString("userID", "");
            String sendID = msg.optString("sendID", "");
            String inviter = data.optString("inviterUserID", sendID);

            if (customType == 200) {
                if (!self.isEmpty() && (self.equals(sendID) || self.equals(inviter))) {
                    return;
                }
                if (HangxunImKeepAlivePoke.isAppVisible()) {
                    notifyDart(app, "showInApp", data, json);
                    return;
                }
                show(app, roomID, inviter, "video".equals(data.optString("mediaType")), data, json);
                return;
            }
            if (customType == 202 || customType == 203 || customType == 204) {
                cancel(app, roomID);
                String action = customType == 202 ? "reject"
                        : customType == 204 ? "hungup" : "cancel";
                notifyDart(app, action, data, json);
            }
        } catch (Throwable t) {
            Log.w(TAG, "parse IM message failed", t);
        }
    }

    static void show(Context app, String roomID, String caller, boolean video,
                     JSONObject data, String json) {
        ringingRoomID = roomID;
        ringingJson = json;
        app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("nativeRinging", true)
                .putString("nativeRingingRoom", roomID)
                .apply();

        wakeScreen(app);
        startRingtone(app);
        postNotification(app, roomID, caller, video, data, json);
        launchUi(app, roomID, caller, video, data, json);
        notifyDart(app, "show", data, json);
    }

    static void accept(Context app, Intent src) {
        String roomID = src != null ? src.getStringExtra(EXTRA_ROOM) : ringingRoomID;
        JSONObject data = extrasToData(src);
        stopRingtone();
        cancelNotification(app);
        app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                .edit().putBoolean("nativeRinging", false).apply();
        launchMain(app, src, true);
        notifyDart(app, "accept", data, ringingJson);
        ringingRoomID = null;
        IncomingCallActivity.finishIfShowing();
    }

    static void reject(Context app, Intent src) {
        JSONObject data = extrasToData(src);
        stopRingtone();
        cancelNotification(app);
        app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                .edit().putBoolean("nativeRinging", false).apply();
        notifyDart(app, "reject", data, ringingJson);
        ringingRoomID = null;
        IncomingCallActivity.finishIfShowing();
    }

    public static void cancel(Context app, String roomID) {
        if (roomID != null && ringingRoomID != null && !roomID.equals(ringingRoomID)) {
            return;
        }
        stopRingtone();
        cancelNotification(app);
        app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                .edit().putBoolean("nativeRinging", false).apply();
        ringingRoomID = null;
        IncomingCallActivity.finishIfShowing();
    }

    private static void launchUi(Context app, String roomID, String caller, boolean video,
                                 JSONObject data, String json) {
        try {
            Intent ui = new Intent(app, IncomingCallActivity.class);
            ui.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_CLEAR_TOP
                    | Intent.FLAG_ACTIVITY_SINGLE_TOP
                    | Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS);
            putExtras(ui, roomID, caller, video, data, json);
            app.startActivity(ui);
        } catch (Throwable t) {
            Log.w(TAG, "launch IncomingCallActivity failed", t);
        }
    }

    private static void launchMain(Context app, Intent src, boolean autoAccept) {
        try {
            Intent i = new Intent(app, MainActivity.class);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_CLEAR_TOP
                    | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            if (src != null && src.getExtras() != null) {
                i.putExtras(src.getExtras());
            }
            i.putExtra("EXTRA_CALLKIT_ID", src != null ? src.getStringExtra(EXTRA_ROOM) : ringingRoomID);
            i.putExtra("id", src != null ? src.getStringExtra(EXTRA_ROOM) : ringingRoomID);
            i.putExtra("EXTRA_CALLKIT_NAME_CALLER",
                    src != null ? src.getStringExtra(EXTRA_CALLER) : "");
            i.putExtra("hangxun.autoAccept", autoAccept);
            app.startActivity(i);
        } catch (Throwable t) {
            Log.w(TAG, "launch MainActivity failed", t);
        }
    }

    private static void postNotification(Context app, String roomID, String caller,
                                         boolean video, JSONObject data, String json) {
        try {
            ensureChannel(app);
            Intent full = new Intent(app, IncomingCallActivity.class);
            full.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            putExtras(full, roomID, caller, video, data, json);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent fullPi = PendingIntent.getActivity(app, 11, full, flags);

            Intent accept = new Intent(app, HangxunIncomingCallReceiver.class);
            accept.setAction(ACTION_ACCEPT);
            putExtras(accept, roomID, caller, video, data, json);
            PendingIntent acceptPi = PendingIntent.getBroadcast(app, 12, accept, flags);

            Intent reject = new Intent(app, HangxunIncomingCallReceiver.class);
            reject.setAction(ACTION_REJECT);
            putExtras(reject, roomID, caller, video, data, json);
            PendingIntent rejectPi = PendingIntent.getBroadcast(app, 13, reject, flags);

            String title = video ? "视频来电" : "语音来电";
            Notification.Builder builder;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder = new Notification.Builder(app, CHANNEL_ID);
            } else {
                builder = new Notification.Builder(app);
            }
            builder.setContentTitle(title)
                    .setContentText(caller + " 邀请你通话")
                    .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setContentIntent(fullPi)
                    .setFullScreenIntent(fullPi, true)
                    .addAction(android.R.drawable.ic_menu_close_clear_cancel, "拒绝", rejectPi)
                    .addAction(android.R.drawable.ic_menu_call, "接听", acceptPi);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.setVisibility(Notification.VISIBILITY_PUBLIC);
                builder.setPriority(Notification.PRIORITY_MAX);
                builder.setCategory(Notification.CATEGORY_CALL);
            }
            NotificationManager nm =
                    (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.notify(NOTIF_ID, builder.build());
        } catch (Throwable t) {
            Log.w(TAG, "post notification failed", t);
        }
    }

    private static void ensureChannel(Context app) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm =
                (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "航讯来电", NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("锁屏来电");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        channel.enableVibration(true);
        channel.setSound(null, null);
        nm.createNotificationChannel(channel);
    }

    private static void cancelNotification(Context app) {
        try {
            NotificationManager nm =
                    (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.cancel(NOTIF_ID);
        } catch (Throwable ignored) {
        }
    }

    private static void startRingtone(Context app) {
        stopRingtone();
        try {
            Uri uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
            ringtone = new MediaPlayer();
            ringtone.setDataSource(app, uri);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                ringtone.setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build());
            } else {
                ringtone.setAudioStreamType(AudioManager.STREAM_RING);
            }
            ringtone.setLooping(true);
            ringtone.prepare();
            ringtone.start();
        } catch (Throwable t) {
            Log.w(TAG, "ringtone failed", t);
            ringtone = null;
        }
        try {
            Vibrator vib;
            if (Build.VERSION.SDK_INT >= 31) {
                VibratorManager vm =
                        (VibratorManager) app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
                vib = vm != null ? vm.getDefaultVibrator() : null;
            } else {
                vib = (Vibrator) app.getSystemService(Context.VIBRATOR_SERVICE);
            }
            if (vib != null) {
                long[] pattern = new long[]{0, 800, 400, 800};
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vib.vibrate(VibrationEffect.createWaveform(pattern, 0));
                } else {
                    vib.vibrate(pattern, 0);
                }
            }
        } catch (Throwable ignored) {
        }
    }

    static void stopRingtone() {
        try {
            if (ringtone != null) {
                ringtone.stop();
                ringtone.release();
            }
        } catch (Throwable ignored) {
        }
        ringtone = null;
        try {
            // Best-effort stop of looping vibration: cancel() on default vibrator
            // is done from IncomingCallActivity.onDestroy as well.
        } catch (Throwable ignored) {
        }
    }

    private static void wakeScreen(Context app) {
        try {
            PowerManager pm = (PowerManager) app.getSystemService(Context.POWER_SERVICE);
            if (pm == null) return;
            @SuppressWarnings("deprecation")
            PowerManager.WakeLock wl = pm.newWakeLock(
                    PowerManager.FULL_WAKE_LOCK
                            | PowerManager.ACQUIRE_CAUSES_WAKEUP
                            | PowerManager.ON_AFTER_RELEASE,
                    "hangxun:incoming");
            wl.setReferenceCounted(false);
            wl.acquire(15000);
        } catch (Throwable ignored) {
        }
    }

    static void putExtras(Intent i, String roomID, String caller, boolean video,
                          JSONObject data, String json) {
        i.putExtra(EXTRA_ROOM, roomID);
        i.putExtra(EXTRA_CALLER, caller == null || caller.isEmpty() ? "来电" : caller);
        i.putExtra(EXTRA_VIDEO, video);
        i.putExtra(EXTRA_INVITER, data != null ? data.optString("inviterUserID") : "");
        i.putExtra(EXTRA_MEDIA, video ? "video" : "audio");
        i.putExtra(EXTRA_TIMEOUT, data != null ? data.optInt("timeout", 60) : 60);
        i.putExtra(EXTRA_JSON, json);
        i.putExtra("EXTRA_CALLKIT_ID", roomID);
        i.putExtra("EXTRA_CALLKIT_NAME_CALLER", caller);
        i.putExtra("id", roomID);
        if (data != null) {
            JSONArray list = data.optJSONArray("inviteeUserIDList");
            if (list != null) i.putExtra("inviteeUserIDList", list.toString());
        }
    }

    private static JSONObject extrasToData(Intent src) {
        JSONObject data = new JSONObject();
        if (src == null) return data;
        try {
            data.put("roomID", src.getStringExtra(EXTRA_ROOM));
            data.put("inviterUserID", src.getStringExtra(EXTRA_INVITER));
            data.put("mediaType", src.getStringExtra(EXTRA_MEDIA));
            data.put("timeout", src.getIntExtra(EXTRA_TIMEOUT, 60));
            String list = src.getStringExtra("inviteeUserIDList");
            if (list != null && !list.isEmpty()) {
                data.put("inviteeUserIDList", new JSONArray(list));
            }
        } catch (Throwable ignored) {
        }
        return data;
    }

    private static void notifyDart(Context app, String action, JSONObject data, String json) {
        try {
            final FlutterEngine engine =
                    FlutterEngineCache.getInstance().get(MainActivity.ENGINE_ID);
            if (engine == null) return;
            final Map<String, Object> payload = new HashMap<>();
            payload.put("action", action);
            payload.put("roomID", data != null ? data.optString("roomID") : "");
            payload.put("inviterUserID", data != null ? data.optString("inviterUserID") : "");
            payload.put("mediaType", data != null ? data.optString("mediaType", "audio") : "audio");
            payload.put("timeout", data != null ? data.optInt("timeout", 60) : 60);
            payload.put("raw", json);
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    new MethodChannel(
                            engine.getDartExecutor().getBinaryMessenger(),
                            "top.hangxun.app/voip")
                            .invokeMethod("nativeIncomingCall", payload);
                } catch (Throwable ignored) {
                }
            });
        } catch (Throwable ignored) {
        }
    }

    public static class HangxunIncomingCallReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (context == null || intent == null) return;
            Context app = context.getApplicationContext();
            String action = intent.getAction();
            if (ACTION_RAW.equals(action)) {
                onRawMessage(app, intent.getStringExtra("json"));
            } else if (ACTION_ACCEPT.equals(action)) {
                accept(app, intent);
            } else if (ACTION_REJECT.equals(action)) {
                reject(app, intent);
            }
        }
    }
}
