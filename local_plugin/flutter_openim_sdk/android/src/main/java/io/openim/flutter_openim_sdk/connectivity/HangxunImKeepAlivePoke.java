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
 * The msggateway idle timeout is ~30–90s. Sending a WS frame every poke
 * (setAppBackgroundStatus) is what actually keeps the connection; a 90s
 * throttle here used to let the server drop the socket after ~1 minute.
 */
public final class HangxunImKeepAlivePoke {
    public static final String ACTION = "io.openim.hangxun.POKE_IM";
    private static final String TAG = "HangxunImKeepAlive";
    private static final long HINT_INTERVAL_MS = 12_000L;
    private static final long RECONNECT_INTERVAL_MS = 20_000L;
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
            // false = still "foreground" to the gateway so invites stay on WS.
            Open_im_sdk.setAppBackgroundStatus(CALLBACK, op, false);
        } catch (Throwable t) {
            Log.e(TAG, "foreground hint failed", t);
            lastHintMs = 0;
        }
    }

    /**
     * Reconnect if the gateway already dropped us. Safe here because the
     * conversation UI is not on screen.
     */
    private static void maybeWakeSocket() {
        if (!FlutterOpenimSdkPlugin.isInitialized) {
            return;
        }
        long now = System.currentTimeMillis();
        long status = LOGIN_LOGGED;
        try {
            status = Open_im_sdk.getLoginStatus(String.valueOf(now));
        } catch (Throwable t) {
            Log.e(TAG, "login status failed", t);
            return;
        }
        boolean disconnected = status != LOGIN_LOGGED;
        if (!disconnected
                && lastReconnectMs > 0
                && now - lastReconnectMs < RECONNECT_INTERVAL_MS) {
            return;
        }
        lastReconnectMs = now;
        if (disconnected) {
            Log.i(TAG, "login status " + status + ", waking socket");
        }
        try {
            Open_im_sdk.networkStatusChanged(CALLBACK, String.valueOf(now));
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
