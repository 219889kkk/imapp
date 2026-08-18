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
 * HangXun Android has no Getui. On lock, tell OpenIM we are still
 * foreground so the websocket keeps delivering.
 *
 * Do not call networkStatusChanged on a timer — that reconnects the
 * socket and the conversation list flashes 「连接中」 then refreshes.
 * Do not repeat setAppBackgroundStatus(false) while the UI is visible:
 * each call wakes a full data sync.
 */
public final class HangxunImKeepAlivePoke {
    public static final String ACTION = "io.openim.hangxun.POKE_IM";
    private static final String TAG = "HangxunImKeepAlive";
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
    private static boolean backgroundHintSent;

    private HangxunImKeepAlivePoke() {}

    public static void onActivityStarted() {
        startedActivities++;
        backgroundHintSent = false;
    }

    public static void onActivityStopped() {
        if (startedActivities > 0) {
            startedActivities--;
        }
        if (startedActivities == 0) {
            keepForegroundHint();
        }
    }

    /** Keep-alive service tick: ignore while the user is in the app. */
    public static void onKeepAliveTick() {
        if (startedActivities > 0) {
            return;
        }
        keepForegroundHint();
    }

    private static void keepForegroundHint() {
        if (!FlutterOpenimSdkPlugin.isInitialized) {
            return;
        }
        if (backgroundHintSent) {
            return;
        }
        backgroundHintSent = true;
        try {
            String op = String.valueOf(System.currentTimeMillis());
            Open_im_sdk.setAppBackgroundStatus(CALLBACK, op, false);
        } catch (Throwable t) {
            Log.e(TAG, "foreground hint failed", t);
            backgroundHintSent = false;
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
