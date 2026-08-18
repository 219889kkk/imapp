package io.openim;

import android.app.KeyguardManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;

import android.content.SharedPreferences;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterFragmentActivity {
    private static final String VOIP_CHANNEL = "top.hangxun.app/voip";
    private static final String ENGINE_ID = "hangxun_engine";
    private static final String PREFS = "hangxun";
    private static final String PREF_LOGIN = "hasLoginSession";

    @Override
    public FlutterEngine provideFlutterEngine(@NonNull android.content.Context context) {
        FlutterEngineCache cache = FlutterEngineCache.getInstance();
        FlutterEngine engine = cache.get(ENGINE_ID);
        if (engine != null) return engine;
        engine = new FlutterEngine(context.getApplicationContext());
        GeneratedPluginRegistrant.registerWith(engine);
        engine.getDartExecutor().executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault());
        cache.put(ENGINE_ID, engine);
        return engine;
    }

    @Override
    public boolean shouldDestroyEngineWithHost() {
        return false;
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (hasLoginSession()) {
            ImKeepAliveService.start(getApplicationContext());
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (hasLoginSession()) {
            ImKeepAliveService.start(getApplicationContext());
        }
    }

    private boolean hasLoginSession() {
        return getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(PREF_LOGIN, false);
    }

    private void setLoginSession(boolean active) {
        SharedPreferences.Editor ed =
                getSharedPreferences(PREFS, MODE_PRIVATE).edit();
        ed.putBoolean(PREF_LOGIN, active);
        ed.apply();
        if (active) {
            ImKeepAliveService.start(getApplicationContext());
        } else {
            ImKeepAliveService.stop(getApplicationContext());
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), VOIP_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "isDeviceLocked":
                            result.success(isDeviceLocked());
                            break;
                        case "unusedAppRestrictionsEnabled":
                            result.success(unusedAppRestrictionsEnabled());
                            break;
                        case "openUnusedAppSettings":
                            result.success(openUnusedAppSettings());
                            break;
                        case "openAutostartSettings":
                            result.success(openAutostartSettings());
                            break;
                        case "setLoginSessionHint":
                            boolean active = Boolean.TRUE.equals(call.argument("active"));
                            setLoginSession(active);
                            result.success(true);
                            break;
                        case "startImKeepAlive":
                            ImKeepAliveService.start(getApplicationContext());
                            result.success(true);
                            break;
                        case "stopImKeepAlive":
                            ImKeepAliveService.stop(getApplicationContext());
                            result.success(true);
                            break;
                        default:
                            result.notImplemented();
                            break;
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

    // Android 12+ "Pause app activity if unused" / auto-reset permissions.
    // true = still restricted, user should turn it off for incoming calls.
    private boolean unusedAppRestrictionsEnabled() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false;
        try {
            PackageManager pm = getPackageManager();
            // Whitelisted = exempt from unused-app pause / auto-revoke.
            return !pm.isAutoRevokeWhitelisted();
        } catch (Throwable t) {
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S;
        }
    }

    private boolean openUnusedAppSettings() {
        String pkg = getPackageName();
        List<Intent> intents = new ArrayList<>();
        Intent unusedPkg = new Intent("android.settings.UNUSED_APP_SETTINGS");
        unusedPkg.setData(Uri.fromParts("package", pkg, null));
        intents.add(unusedPkg);
        intents.add(new Intent("android.settings.UNUSED_APP_SETTINGS"));
        Intent autoRevoke = new Intent("android.intent.action.AUTO_REVOKE_PERMISSIONS");
        autoRevoke.setData(Uri.fromParts("package", pkg, null));
        intents.add(autoRevoke);
        Intent details = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        details.setData(Uri.fromParts("package", pkg, null));
        intents.add(details);
        return startFirstResolvable(intents);
    }

    private boolean openAutostartSettings() {
        String brand = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.toLowerCase(Locale.US);
        List<Intent> intents = new ArrayList<>();
        if (containsAny(brand, "xiaomi", "redmi", "poco", "blackshark")) {
            addComponent(intents, "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity");
            intents.add(new Intent("miui.intent.action.OP_AUTO_START")
                    .addCategory(Intent.CATEGORY_DEFAULT));
        } else if (containsAny(brand, "huawei", "honor")) {
            addComponent(intents, "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity");
            addComponent(intents, "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity");
            addComponent(intents, "com.hihonor.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity");
        } else if (containsAny(brand, "oppo", "realme", "oneplus")) {
            addComponent(intents, "com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity");
            addComponent(intents, "com.oplus.safecenter",
                    "com.oplus.safecenter.startupapp.StartupAppListActivity");
            addComponent(intents, "com.coloros.safecenter",
                    "com.coloros.privacypermissionsentry.PermissionTopActivity");
        } else if (containsAny(brand, "vivo", "iqoo")) {
            addComponent(intents, "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity");
            addComponent(intents, "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity");
        } else if (containsAny(brand, "samsung")) {
            addComponent(intents, "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity");
        } else if (containsAny(brand, "meizu")) {
            intents.add(new Intent("com.meizu.safe.security.SHOW_APPSEC")
                    .addCategory(Intent.CATEGORY_DEFAULT)
                    .putExtra("packageName", getPackageName()));
        }
        intents.add(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
        Intent details = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        details.setData(Uri.fromParts("package", getPackageName(), null));
        intents.add(details);
        return startFirstResolvable(intents);
    }

    private void addComponent(List<Intent> intents, String pkg, String cls) {
        Intent i = new Intent();
        i.setComponent(new ComponentName(pkg, cls));
        intents.add(i);
    }

    private boolean startFirstResolvable(List<Intent> intents) {
        PackageManager pm = getPackageManager();
        for (Intent intent : intents) {
            if (intent == null) continue;
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                if (intent.resolveActivity(pm) != null) {
                    startActivity(intent);
                    return true;
                }
            } catch (Throwable ignored) {}
        }
        return false;
    }

    private static boolean containsAny(String brand, String... names) {
        for (String n : names) {
            if (brand.contains(n)) return true;
        }
        return false;
    }
}
