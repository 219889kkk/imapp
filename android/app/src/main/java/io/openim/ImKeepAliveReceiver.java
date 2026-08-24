package io.openim;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Doze-proof tick. HandlerThread delays are frozen after ~1 minute of lock;
 * AlarmManager.setExactAndAllowWhileIdle still runs.
 */
public class ImKeepAliveReceiver extends BroadcastReceiver {
    public static final String ACTION = "io.openim.KEEPALIVE_ALARM";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (context == null) return;
        String action = intent != null ? intent.getAction() : null;
        if (ACTION.equals(action)
                || Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            ImKeepAliveService.onAlarm(context.getApplicationContext());
        }
    }
}
