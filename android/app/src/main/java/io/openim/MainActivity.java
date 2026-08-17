package io.openim;

import android.app.KeyguardManager;
import android.content.Context;
import android.os.PowerManager;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {
    private static final String VOIP_CHANNEL = "top.hangxun.app/voip";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), VOIP_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("isDeviceLocked".equals(call.method)) {
                        result.success(isDeviceLocked());
                    } else {
                        result.notImplemented();
                    }
                });
    }

    private boolean isDeviceLocked() {
        KeyguardManager km = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        boolean keyguard = km != null && km.isKeyguardLocked();
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        boolean screenOff = pm != null && !pm.isInteractive();
        return keyguard || screenOff;
    }
}
