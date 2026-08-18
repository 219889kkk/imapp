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
 * HangXun Android has no Getui. Keep telling OpenIM we are foreground
 * so lock-screen text/calls still arrive on the websocket.
 *
 * The app process pokes via broadcast so :app does not compile against
 * open_im_sdk_callback.Base (that class lives only in the SDK AAR).
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

    private HangxunImKeepAlivePoke() {}

    public static void poke() {
        if (!FlutterOpenimSdkPlugin.isInitialized) {
            return;
        }
        try {
            String op = String.valueOf(System.currentTimeMillis());
            Open_im_sdk.setAppBackgroundStatus(CALLBACK, op, false);
            Open_im_sdk.networkStatusChanged(CALLBACK, op + "-n");
        } catch (Throwable t) {
            Log.e(TAG, "poke failed", t);
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
                    poke();
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
