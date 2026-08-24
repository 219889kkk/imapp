package io.openim;

import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
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

import java.util.ArrayList;
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
    public static final String ACTION_DISMISS = "io.openim.hangxun.CALL_DISMISS";
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
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private static MediaPlayer ringtone;
    private static Vibrator vibrator;
    private static String ringingRoomID;
    private static String ringingJson;
    private static volatile boolean dismissed = true;
    private static volatile boolean accepting;
    private static int acceptGen;
    private static Context appCtx;
    private static final Runnable AUTO_DISMISS = () -> {
        try {
            if (appCtx != null) cancel(appCtx, ringingRoomID);
        } catch (Throwable ignored) {
        }
    };

    private HangxunIncomingCall() {}

    public static void onRawMessage(Context context, String json) {
        if (context == null || json == null || json.isEmpty()) return;
        Context app = context.getApplicationContext();
        try {
            JSONObject msg = new JSONObject(json);
            JSONObject payload = extractPayload(msg);
            if (payload == null) return;
            int customType = readInt(payload, "customType");
            JSONObject data = payload.optJSONObject("data");
            if (data == null) data = new JSONObject();
            String roomID = data.optString("roomID", "").trim();

            String self = app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                    .getString("userID", "");
            String sendID = msg.optString("sendID", "");
            String inviter = data.optString("inviterUserID", sendID);

            // Hangup / cancel / reject / accept must always kill the native ringer.
            if (customType == 201 || customType == 202
                    || customType == 203 || customType == 204) {
                cancel(app, roomID);
                String action = customType == 202 ? "reject"
                        : customType == 201 ? "accept"
                        : customType == 204 ? "hungup" : "cancel";
                notifyDart(app, action, data, json);
                return;
            }
            if (customType != 200) return;
            if (roomID.isEmpty()) return;
            if (!self.isEmpty() && (self.equals(sendID) || self.equals(inviter))) {
                return;
            }
            if (HangxunImKeepAlivePoke.isAppVisible()
                    && IncomingCallActivity.current() == null) {
                notifyDart(app, "showInApp", data, json);
                return;
            }
            show(app, roomID, inviter, "video".equals(data.optString("mediaType")), data, json);
        } catch (Throwable t) {
            Log.w(TAG, "parse IM message failed", t);
        }
    }

    private static JSONObject extractPayload(JSONObject msg) {
        try {
            JSONObject customElem = msg.optJSONObject("customElem");
            Object dataRaw = customElem != null ? customElem.opt("data") : null;
            if (dataRaw == null) dataRaw = msg.opt("content");
            if (dataRaw == null) return null;
            if (dataRaw instanceof JSONObject) return (JSONObject) dataRaw;
            String s = String.valueOf(dataRaw).trim();
            if (s.isEmpty() || s.charAt(0) != '{') return null;
            return new JSONObject(s);
        } catch (Throwable t) {
            return null;
        }
    }

    private static int readInt(JSONObject o, String key) {
        if (o == null) return 0;
        Object v = o.opt(key);
        if (v instanceof Number) return ((Number) v).intValue();
        if (v instanceof String) {
            try {
                return Integer.parseInt(((String) v).trim());
            } catch (Throwable ignored) {
            }
        }
        return 0;
    }

    static void show(Context app, String roomID, String caller, boolean video,
                     JSONObject data, String json) {
        appCtx = app.getApplicationContext();
        dismissed = false;
        accepting = false;
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
        MAIN.removeCallbacks(AUTO_DISMISS);
        int timeoutSec = readInt(data, "timeout");
        if (timeoutSec < 30) timeoutSec = 60;
        MAIN.postDelayed(AUTO_DISMISS, timeoutSec * 1000L);
    }

    static void accept(Context app, Intent src) {
        JSONObject data = extrasToData(src);
        String json = ringingJson;
        try {
            if (data.optString("inviterUserID", "").trim().isEmpty()) {
                String caller = src != null ? src.getStringExtra(EXTRA_CALLER) : "";
                if (caller != null && !caller.isEmpty() && !"来电".equals(caller)) {
                    data.put("inviterUserID", caller);
                }
            }
        } catch (Throwable ignored) {
        }
        // IncomingCallActivity uses empty taskAffinity. Finishing it before
        // MainActivity is in front sends the user to the launcher with no
        // in-app call page.
        stopRingtone();
        if (app != null) {
            cancelNotification(app);
            app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                    .edit().putBoolean("nativeRinging", false).apply();
        }
        dismissed = true;
        MAIN.removeCallbacks(AUTO_DISMISS);
        accepting = true;
        final int gen = ++acceptGen;
        launchMain(app, src, true);
        bringMainToFront(app);
        final JSONObject payload = data;
        final String raw = json;
        MAIN.postDelayed(() -> {
            if (gen != acceptGen) return;
            accepting = false;
            try {
                IncomingCallActivity.finishIfShowing();
            } catch (Throwable ignored) {
            }
            ringingRoomID = null;
            ringingJson = null;
            notifyDart(app, "accept", payload, raw);
        }, 450);
    }

    static void reject(Context app, Intent src) {
        JSONObject data = extrasToData(src);
        String json = ringingJson;
        dismissLocal(app);
        notifyDart(app, "reject", data, json);
    }

    public static void cancel(Context app, String roomID) {
        if (roomID != null && !roomID.isEmpty()
                && ringingRoomID != null && !roomID.equals(ringingRoomID)) {
            Log.i(TAG, "cancel ignored other room " + roomID + " ringing " + ringingRoomID);
            return;
        }
        dismissLocal(app);
    }

    public static boolean shouldShow(String roomID) {
        if (accepting) return true;
        if (dismissed) return false;
        if (ringingRoomID == null || ringingRoomID.isEmpty()) return false;
        return roomID == null || roomID.isEmpty() || ringingRoomID.equals(roomID);
    }

    private static void dismissLocal(Context app) {
        accepting = false;
        acceptGen++;
        dismissed = true;
        MAIN.removeCallbacks(AUTO_DISMISS);
        stopRingtone();
        if (app != null) {
            cancelNotification(app);
            app.getSharedPreferences("hangxun", Context.MODE_PRIVATE)
                    .edit().putBoolean("nativeRinging", false).apply();
            try {
                Intent i = new Intent(ACTION_DISMISS);
                i.setPackage(app.getPackageName());
                app.sendBroadcast(i);
            } catch (Throwable ignored) {
            }
        }
        ringingRoomID = null;
        ringingJson = null;
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
            Context from = IncomingCallActivity.current();
            if (from == null) from = app;
            Intent i = new Intent(from, MainActivity.class);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    | Intent.FLAG_ACTIVITY_CLEAR_TOP
                    | Intent.FLAG_ACTIVITY_SINGLE_TOP
                    | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            if (src != null && src.getExtras() != null) {
                i.putExtras(src.getExtras());
            }
            i.putExtra("EXTRA_CALLKIT_ID", src != null ? src.getStringExtra(EXTRA_ROOM) : ringingRoomID);
            i.putExtra("id", src != null ? src.getStringExtra(EXTRA_ROOM) : ringingRoomID);
            i.putExtra("EXTRA_CALLKIT_NAME_CALLER",
                    src != null ? src.getStringExtra(EXTRA_CALLER) : "");
            i.putExtra("hangxun.autoAccept", autoAccept);
            from.startActivity(i);
        } catch (Throwable t) {
            Log.w(TAG, "launch MainActivity failed", t);
        }
    }

    private static void bringMainToFront(Context app) {
        if (app == null) return;
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return;
            ActivityManager am = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return;
            for (ActivityManager.AppTask task : am.getAppTasks()) {
                ActivityManager.RecentTaskInfo info = task.getTaskInfo();
                if (info == null) continue;
                ComponentName cn = info.baseActivity != null ? info.baseActivity : info.origActivity;
                if (cn == null) cn = info.topActivity;
                if (cn == null) continue;
                if (MainActivity.class.getName().equals(cn.getClassName())) {
                    task.moveToFront();
                    return;
                }
            }
        } catch (Throwable ignored) {
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
                vibrator = vib;
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
            if (vibrator != null) vibrator.cancel();
        } catch (Throwable ignored) {
        }
        vibrator = null;
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
        String inviterId = data != null ? data.optString("inviterUserID") : "";
        if (inviterId == null || inviterId.trim().isEmpty()) {
            inviterId = caller == null ? "" : caller;
        }
        i.putExtra(EXTRA_INVITER, inviterId);
        i.putExtra(EXTRA_MEDIA, video ? "video" : "audio");
        i.putExtra(EXTRA_TIMEOUT, data != null ? readInt(data, "timeout") : 60);
        i.putExtra(EXTRA_JSON, json);
        i.putExtra("EXTRA_CALLKIT_ID", roomID);
        i.putExtra("EXTRA_CALLKIT_NAME_CALLER", caller);
        i.putExtra("id", roomID);
        i.putExtra("sessionType", data != null ? readInt(data, "sessionType") : 1);
        i.putExtra("groupID", data != null ? data.optString("groupID") : "");
        if (data != null) {
            JSONArray list = data.optJSONArray("inviteeUserIDList");
            if (list != null) i.putExtra("inviteeUserIDList", list.toString());
        }
    }

    private static JSONObject extrasToData(Intent src) {
        JSONObject data = new JSONObject();
        if (src == null) return data;
        try {
            String inviter = src.getStringExtra(EXTRA_INVITER);
            if (inviter == null || inviter.trim().isEmpty()) {
                inviter = src.getStringExtra(EXTRA_CALLER);
            }
            data.put("roomID", src.getStringExtra(EXTRA_ROOM));
            data.put("inviterUserID", inviter == null ? "" : inviter);
            data.put("mediaType", src.getStringExtra(EXTRA_MEDIA));
            data.put("timeout", src.getIntExtra(EXTRA_TIMEOUT, 60));
            data.put("sessionType", src.getIntExtra("sessionType", 1));
            data.put("groupID", src.getStringExtra("groupID"));
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
            payload.put("sessionType", data != null ? readInt(data, "sessionType") : 1);
            payload.put("groupID", data != null ? data.optString("groupID") : "");
            payload.put("raw", json);
            if (data != null) {
                JSONArray arr = data.optJSONArray("inviteeUserIDList");
                if (arr != null) {
                    ArrayList<String> list = new ArrayList<>();
                    for (int n = 0; n < arr.length(); n++) {
                        String id = arr.optString(n);
                        if (id != null && !id.isEmpty()) list.add(id);
                    }
                    payload.put("inviteeUserIDList", list);
                }
            }
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
