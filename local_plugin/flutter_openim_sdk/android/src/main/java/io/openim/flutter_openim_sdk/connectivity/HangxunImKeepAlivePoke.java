package io.openim.flutter_openim_sdk.connectivity;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;

import io.flutter.Log;
import io.openim.flutter_openim_sdk.FlutterOpenimSdkPlugin;
import open_im_sdk.Open_im_sdk;

/**
 * HangXun Android has no Getui. On lock, keep the IM websocket delivering.
 *
 * Do not call networkStatusChanged while the UI is visible — that reconnects
 * and the conversation list flashes 「连接中」.
 * While locked, NAT / Doze drop the socket after a few minutes unless we
 * actually ping native OpenIM (the 20s broadcast used to no-op after the
 * first setAppBackgroundStatus).
 */
public final class HangxunImKeepAlivePoke {
    public static final String ACTION = "io.openim.hangxun.POKE_IM";
    private static final String TAG = "HangxunImKeepAlive";
    private static final long HINT_INTERVAL_MS = 90_000L;
    private static final long RECONNECT_INTERVAL_MS = 45_000L;
    private static final int LOGIN_LOGGED = 3;
    private static final open_im_sdk_callback.Base CALLBACK = new open_im_sdk_callback.Base() {
        @Override
        public void onError(int i, String s) {
            Log.i(TAG, "poke error " + i + " " + s);
        }

        @Override
        public void onSuccess(String s) {
        }
    };

    private static BroadcastReceiver receiver;
    private static int startedActivities;
    private static long lastHintMs;
    private static long lastReconnectMs;

    private HangxunImKeepAlivePoke() {}

    public static void onActivityStarted() {
        startedActivities++;
        lastHintMs = 0;
        lastReconnectMs = 0;
    }

    public static void onActivityStopped() {
        if (startedActivities > 0) {
            startedActivities--;
        }
        if (startedActivities == 0) {
            keepForegroundHint(true);
        }
    }

    /** Keep-alive service tick: ignore while the user is in the app. */
    public static void onKeepAliveTick() {
        if (startedActivities > 0) {
            return;
        }
        keepForegroundHint(false);
        maybeWakeSocket();
    }

    private static void keepForegroundHint(boolean force) {
        if (!FlutterOpenimSdkPlugin.isInitialized) {
            return;
        }
        long now = System.currentTimeMillis();
        if (!force && lastHintMs > 0 && now - lastHintMs < HINT_INTERVAL_MS) {
            return;
        }
        lastHintMs = now;
        try {
            String op = String.valueOf(now);
            Open_im_sdk.setAppBackgroundStatus(CALLBACK, op, false);
        } catch (Throwable t) {
            Log.e(TAG, "foreground hint failed", t);
            lastHintMs = 0;
        }
    }

    /**
     * Ping / reconnect the IM websocket while locked. Safe here because the
     * conversation UI is not on screen.
     */
    private static void maybeWakeSocket() {
        if (!FlutterOpenimSdkPlugin.isInitialized) {
            return;
        }
        long now = System.currentTimeMillis();
        if (lastReconnectMs > 0 && now - lastReconnectMs < RECONNECT_INTERVAL_MS) {
            return;
        }
        lastReconnectMs = now;
        try {
            String op = String.valueOf(now);
            long status = Open_im_sdk.getLoginStatus(op);
            if (status != LOGIN_LOGGED) {
                Log.i(TAG, "login status " + status + ", waking socket");
            }
            Open_im_sdk.networkStatusChanged(CALLBACK, op);
        } catch (Throwable t) {
            Log.e(TAG, "socket wake failed", t);
            lastReconnectMs = 0;
        }
    }

    public static synchronized void register(Context context) {
        if (context == null || receiver != null) {
            return;
        }
        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context ctx, Intent intent) {
                if (intent != null && ACTION.equals(intent.getAction())) {
                    onKeepAliveTick();
                }
            }
        };
        IntentFilter filter = new IntentFilter(ACTION);
        Context app = context.getApplicationContext();
        if (Build.VERSION.SDK_INT >= 33) {
            app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            app.registerReceiver(receiver, filter);
        }
    }

    public static synchronized void unregister(Context context) {
        if (context == null || receiver == null) {
            return;
        }
        try {
            context.getApplicationContext().unregisterReceiver(receiver);
        } catch (Throwable ignored) {
        }
        receiver = null;
    }
}
