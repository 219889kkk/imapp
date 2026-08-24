package io.openim;

import android.app.ActivityManager;
import android.app.KeyguardManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.provider.Settings;

import android.content.SharedPreferences;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.lifecycle.Lifecycle;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterFragmentActivity {
    private static final String VOIP_CHANNEL = "top.hangxun.app/voip";
    public static final String ENGINE_ID = "hangxun_engine";
    private static final String PREFS = "hangxun";
    private static final String PREF_LOGIN = "hasLoginSession";
    /**
     * After this long stopped, the stale GPU surface will crash on resume.
     * Restart the Activity transparently so it gets a new surface.
     * The engine/dart is kept alive in FlutterEngineCache — IM WS stays connected.
     */
    private static final long STALE_SURFACE_MS = 4 * 60 * 1000L;

    private static WeakReference<MainActivity> current;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private long stoppedAtElapsed;
    private boolean abandonThisInstance;
    private boolean callUiActive;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        current = new WeakReference<>(this);
        // Restoring a frozen Flutter fragment after a long lock crashes on arm64.
        super.onCreate(null);
        applyLockScreenPolicy(getIntent());
    }

    @Override
    @NonNull
    public RenderMode getRenderMode() {
        // TextureView survives brief lock better than SurfaceView on Mali/Adreno.
        return RenderMode.texture;
    }

    private static MainActivity peek() {
        return current == null ? null : current.get();
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        applyLockScreenPolicy(intent);
    }

    /**
     * Always-on showWhenLocked draws Flutter over the keyguard. After a long
     * lock that surface is invalid and tapping the keep-alive notification
     * SIGSEGVs. Only cover the lock screen for an actual incoming call.
     */
    private void applyLockScreenPolicy(@Nullable Intent intent) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return;
        boolean call = isCallIntent(intent);
        try {
            setShowWhenLocked(call);
            setTurnScreenOn(call);
        } catch (Throwable ignored) {
        }
    }

    private boolean isCallIntent(@Nullable Intent intent) {
        if (intent == null) return false;
        if (intent.hasExtra("EXTRA_CALLKIT_ID")
                || intent.hasExtra("EXTRA_CALLKIT_NAME_CALLER")
                || intent.hasExtra("id")) {
            return true;
        }
        String action = intent.getAction();
        if (action != null) {
            String lower = action.toLowerCase(Locale.US);
            if (lower.contains("callkit") || lower.contains("incoming_call")) return true;
        }
        Uri data = intent.getData();
        return data != null && String.valueOf(data).toLowerCase(Locale.US).contains("call");
    }

    /**
     * Keep the Dart/engine alive in cache so the IM WebSocket stays connected
     * after the Activity is gone (lock, home, recents).
     * The Activity will be recreated on next tap; the engine is reused.
     */
    @Override
    public FlutterEngine provideFlutterEngine(@NonNull android.content.Context context) {
        FlutterEngineCache cache = FlutterEngineCache.getInstance();
        FlutterEngine engine = cache.get(ENGINE_ID);
        if (engine == null) {
            engine = new FlutterEngine(context.getApplicationContext());
            GeneratedPluginRegistrant.registerWith(engine);
            engine.getDartExecutor().executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault());
            cache.put(ENGINE_ID, engine);
        }
        return engine;
    }

    /**
     * Never destroy the cached engine when the Activity is destroyed.
     * The engine keeps the Dart isolate + IM WebSocket alive.
     */
    @Override
    public boolean shouldDestroyEngineWithHost() {
        return false;
    }

    @Override
    public boolean shouldAttachEngineToActivity() {
        return !abandonThisInstance;
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
        stoppedAtElapsed = SystemClock.elapsedRealtime();
        super.onStop();
        if (hasLoginSession()) {
            ImKeepAliveService.start(getApplicationContext());
        }
    }

    @Override
    protected void onDestroy() {
        if (current != null && current.get() == this) {
            current.clear();
        }
        super.onDestroy();
    }

    @Override
    protected void onRestart() {
        long gone = stoppedAtElapsed <= 0
                ? 0
                : SystemClock.elapsedRealtime() - stoppedAtElapsed;
        if (gone >= STALE_SURFACE_MS && !isFinishing() && !isCallActive()) {
            // The GPU surface is likely stale. Restart the Activity so Flutter
            // gets a fresh surface — but the cached engine stays alive (WS connected).
            abandonThisInstance = true;
            Intent intent = new Intent(this, MainActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            Intent src = getIntent();
            if (src != null) {
                if (src.getExtras() != null) intent.putExtras(src);
                intent.setData(src.getData());
                if (src.getAction() != null) intent.setAction(src.getAction());
            }
            super.onRestart();
            try {
                startActivity(intent);
            } catch (Throwable ignored) {
            }
            finish();
            overridePendingTransition(0, 0);
            return;
        }
        super.onRestart();
    }

    @SuppressWarnings("deprecation")
    private boolean isCallActive() {
        if (callUiActive) return true;
        if (isCallIntent(getIntent())) return true;
        try {
            ActivityManager am = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
            if (am == null) return false;
            for (ActivityManager.RunningServiceInfo info : am.getRunningServices(32)) {
                String n = info.service != null ? info.service.getClassName() : "";
                if (n.contains("IsolateHolderService") || n.contains("CallService")) {
                    return true;
                }
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    private boolean hasLoginSession() {
        return getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(PREF_LOGIN, false);
    }

    private void setLoginSession(boolean active, String userID) {
        SharedPreferences.Editor ed =
                getSharedPreferences(PREFS, MODE_PRIVATE).edit();
        ed.putBoolean(PREF_LOGIN, active);
        if (userID != null) {
            ed.putString("userID", userID);
        }
        if (!active) {
            ed.remove("userID");
        }
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
                        case "getCallPermGuide":
                            result.success(getCallPermGuide());
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
                            String userID = call.argument("userID");
                            setLoginSession(active, userID);
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
                        case "stopNativeIncoming":
                            HangxunIncomingCall.cancel(
                                    getApplicationContext(),
                                    call.argument("roomID"));
                            result.success(true);
                            break;
                        case "setCallUiActive":
                            callUiActive = Boolean.TRUE.equals(call.argument("active"));
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

    // Which OEM pages actually exist on this phone — do not nag for missing UIs.
    private Map<String, Object> getCallPermGuide() {
        String family = oemFamily();
        List<Intent> autoIntents = oemAutostartIntents();
        boolean hasAutostart = !autoIntents.isEmpty() && hasResolvable(autoIntents);
        boolean hasHibernation = hasResolvable(hibernationIntents());
        boolean hibernationOn = hasHibernation && unusedAppRestrictionsEnabled();
        Map<String, Object> out = new HashMap<>();
        out.put("family", family);
        out.put("hasAutostart", hasAutostart);
        out.put("hasHibernation", hasHibernation);
        out.put("hibernationOn", hibernationOn);
        return out;
    }

    private String oemFamily() {
        String brand = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.toLowerCase(Locale.US);
        String model = Build.BRAND == null ? "" : Build.BRAND.toLowerCase(Locale.US);
        String all = brand + " " + model;
        if (containsAny(all, "xiaomi", "redmi", "poco", "blackshark")) return "xiaomi";
        if (containsAny(all, "huawei", "honor")) return "huawei";
        if (containsAny(all, "oppo", "realme", "oneplus")) return "oppo";
        if (containsAny(all, "vivo", "iqoo")) return "vivo";
        if (containsAny(all, "samsung")) return "samsung";
        if (containsAny(all, "meizu")) return "meizu";
        return "stock";
    }

    private List<Intent> oemAutostartIntents() {
        String family = oemFamily();
        List<Intent> intents = new ArrayList<>();
        if ("xiaomi".equals(family)) {
            addComponent(intents, "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity");
            intents.add(new Intent("miui.intent.action.OP_AUTO_START")
                    .addCategory(Intent.CATEGORY_DEFAULT));
        } else if ("huawei".equals(family)) {
            addComponent(intents, "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity");
            addComponent(intents, "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity");
            addComponent(intents, "com.hihonor.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity");
        } else if ("oppo".equals(family)) {
            addComponent(intents, "com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity");
            addComponent(intents, "com.oplus.safecenter",
                    "com.oplus.safecenter.startupapp.StartupAppListActivity");
            addComponent(intents, "com.coloros.safecenter",
                    "com.coloros.privacypermissionsentry.PermissionTopActivity");
        } else if ("vivo".equals(family)) {
            addComponent(intents, "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity");
            addComponent(intents, "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity");
        } else if ("meizu".equals(family)) {
            intents.add(new Intent("com.meizu.safe.security.SHOW_APPSEC")
                    .addCategory(Intent.CATEGORY_DEFAULT)
                    .putExtra("packageName", getPackageName()));
        }
        return intents;
    }

    private List<Intent> hibernationIntents() {
        String pkg = getPackageName();
        List<Intent> intents = new ArrayList<>();
        // App info / 权限页 — this is where 「暂停闲置应用的活动」 lives.
        // UNUSED_APP_SETTINGS is a system list and often misses the toggle.
        Intent details = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        details.setData(Uri.fromParts("package", pkg, null));
        intents.add(details);
        addOemAppPermissionPage(intents, pkg);
        Intent autoRevoke = new Intent("android.intent.action.AUTO_REVOKE_PERMISSIONS");
        autoRevoke.setData(Uri.fromParts("package", pkg, null));
        intents.add(autoRevoke);
        Intent unusedPkg = new Intent("android.settings.UNUSED_APP_SETTINGS");
        unusedPkg.setData(Uri.fromParts("package", pkg, null));
        intents.add(unusedPkg);
        return intents;
    }

    private void addOemAppPermissionPage(List<Intent> intents, String pkg) {
        String family = oemFamily();
        if ("xiaomi".equals(family)) {
            Intent editor = new Intent("miui.intent.action.APP_PERM_EDITOR");
            editor.setClassName("com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity");
            editor.putExtra("extra_pkgname", pkg);
            intents.add(editor);
        } else if ("huawei".equals(family)) {
            Intent hw = new Intent();
            hw.setClassName("com.huawei.systemmanager",
                    "com.huawei.permissionmanager.ui.MainActivity");
            hw.putExtra("packageName", pkg);
            intents.add(hw);
        } else if ("oppo".equals(family)) {
            Intent oppo = new Intent();
            oppo.setClassName("com.coloros.safecenter",
                    "com.coloros.privacypermissionsentry.PermissionTopActivity");
            oppo.putExtra("packageName", pkg);
            intents.add(oppo);
        } else if ("vivo".equals(family)) {
            Intent vivo = new Intent();
            vivo.setClassName("com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.SoftPermissionDetailActivity");
            vivo.putExtra("packagename", pkg);
            intents.add(vivo);
        }
    }

    private boolean hasResolvable(List<Intent> intents) {
        PackageManager pm = getPackageManager();
        for (Intent intent : intents) {
            if (intent == null) continue;
            try {
                if (intent.resolveActivity(pm) != null) return true;
            } catch (Throwable ignored) {}
        }
        return false;
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
        return startFirstResolvable(hibernationIntents());
    }

    private boolean openAutostartSettings() {
        List<Intent> intents = new ArrayList<>(oemAutostartIntents());
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
