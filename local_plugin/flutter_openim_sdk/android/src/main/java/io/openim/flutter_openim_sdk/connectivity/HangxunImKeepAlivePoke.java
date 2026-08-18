package io.openim.flutter_openim_sdk.connectivity;

import io.flutter.Log;
import io.openim.flutter_openim_sdk.FlutterOpenimSdkPlugin;
import open_im_sdk.Open_im_sdk;

/**
 * HangXun Android has no Getui. The process can stay alive (FGS
 * notification still showing) while OpenIM has already marked the
 * session background and stopped delivering live recvNewMessage.
 * Keep telling the SDK we are foreground so lock-screen text/calls
 * still arrive on the websocket.
 */
public final class HangxunImKeepAlivePoke implements open_im_sdk_callback.Base {
    private static final String TAG = "HangxunImKeepAlive";
    private static final HangxunImKeepAlivePoke INSTANCE = new HangxunImKeepAlivePoke();

    private HangxunImKeepAlivePoke() {}

    public static void poke() {
        if (!FlutterOpenimSdkPlugin.isInitialized) {
            return;
        }
        try {
            String op = String.valueOf(System.currentTimeMillis());
            Open_im_sdk.setAppBackgroundStatus(INSTANCE, op, false);
            Open_im_sdk.networkStatusChanged(INSTANCE, op + "-n");
        } catch (Throwable t) {
            Log.e(TAG, "poke failed", t);
        }
    }

    @Override
    public void onError(int i, String s) {
        Log.i(TAG, "poke error " + i + " " + s);
    }

    @Override
    public void onSuccess(String s) {
    }
}
