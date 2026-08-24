package io.openim;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.plugin.common.MethodChannel;


/**
 * Always-on while logged in. HangXun Android has no Getui, so the IM
 * websocket only survives lock/Doze if this service is already running
 * before the screen turns off.
 */
public class ImKeepAliveService extends Service {
    public static final String ACTION_START = "io.openim.KEEPALIVE_START";
    public static final String ACTION_STOP = "io.openim.KEEPALIVE_STOP";
    private static final String TAG = "HangxunKeepAlive";
    private static final String CHANNEL_ID = "hangxun_im_keepalive";
    private static final int NOTIF_ID = 71002;
    private static final long POKE_INTERVAL_MS = 20_000L;

    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;
    private HandlerThread pokeThread;
    private Handler pokeHandler;
    private BroadcastReceiver screenReceiver;
    private final Runnable pokeRunnable = new Runnable() {
        @Override
        public void run() {
            try {
                Intent poke = new Intent("io.openim.hangxun.POKE_IM");
                poke.setPackage(getPackageName());
                sendBroadcast(poke);
                acquireLocks();
                wakeFlutter();
            } catch (Throwable t) {
                Log.w(TAG, "im poke skipped", t);
            }
            if (pokeHandler != null) {
                pokeHandler.postDelayed(this, POKE_INTERVAL_MS);
            }
        }
    };

    public static void start(Context context) {
        if (context == null) return;
        try {
            Intent intent = new Intent(context, ImKeepAliveService.class);
            intent.setAction(ACTION_START);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
        } catch (Throwable t) {
            Log.e(TAG, "start failed", t);
        }
    }

    public static void stop(Context context) {
        if (context == null) return;
        Intent intent = new Intent(context, ImKeepAliveService.class);
        intent.setAction(ACTION_STOP);
        try {
            context.startService(intent);
        } catch (Throwable t) {
            try {
                context.stopService(new Intent(context, ImKeepAliveService.class));
            } catch (Throwable ignored) {
            }
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopPoke();
            releaseLocks();
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            ensureChannel();
            Notification notification = buildNotification();
            if (Build.VERSION.SDK_INT >= 34) {
                try {
                    startForeground(
                            NOTIF_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                                    | ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING);
                } catch (Throwable t) {
                    Log.w(TAG, "remoteMessaging FGS type unavailable, dataSync only", t);
                    startForeground(
                            NOTIF_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
                }
            } else {
                startForeground(NOTIF_ID, notification);
            }
            acquireLocks();
            startPoke();
            registerScreenReceiver();
        } catch (Throwable t) {
            Log.e(TAG, "foreground start failed", t);
            stopSelf();
            return START_NOT_STICKY;
        }
        return START_STICKY;
    }

    @Override
    public void onTimeout(int startId, int fgsType) {
        Log.w(TAG, "foreground timeout type=" + fgsType);
        try {
            stopPoke();
            releaseLocks();
            stopForeground(true);
        } catch (Throwable ignored) {
        }
        stopSelf();
    }

    @Override
    public void onDestroy() {
        unregisterScreenReceiver();
        stopPoke();
        releaseLocks();
        super.onDestroy();
    }

    private void registerScreenReceiver() {
        if (screenReceiver != null) return;
        screenReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (intent == null) return;
                String action = intent.getAction();
                // Screen events handled by MainActivity.onStop/onStart lifecycle.
                // No-op here — keep receiver registered to avoid re-registration cost.
            }
        };
        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_SCREEN_OFF);
        filter.addAction(Intent.ACTION_SCREEN_ON);
        filter.addAction(Intent.ACTION_USER_PRESENT);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(screenReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                registerReceiver(screenReceiver, filter);
            }
        } catch (Throwable t) {
            Log.w(TAG, "screen receiver failed", t);
            screenReceiver = null;
        }
    }

    private void unregisterScreenReceiver() {
        if (screenReceiver == null) return;
        try {
            unregisterReceiver(screenReceiver);
        } catch (Throwable ignored) {
        }
        screenReceiver = null;
    }

    private void startPoke() {
        if (pokeThread == null) {
            pokeThread = new HandlerThread("hangxun-im-poke");
            pokeThread.start();
            pokeHandler = new Handler(pokeThread.getLooper());
        }
        pokeHandler.removeCallbacks(pokeRunnable);
        pokeHandler.post(pokeRunnable);
    }

    private void stopPoke() {
        if (pokeHandler != null) {
            pokeHandler.removeCallbacks(pokeRunnable);
        }
        pokeHandler = null;
        if (pokeThread != null) {
            pokeThread.quitSafely();
            pokeThread = null;
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm == null) return;
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "航讯保持连接",
                NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("锁屏来电需要保持连接");
        channel.setShowBadge(false);
        channel.enableVibration(false);
        channel.setSound(null, null);
        nm.createNotificationChannel(channel);
    }

    private Notification buildNotification() {
        Intent launch = new Intent(this, MainActivity.class);
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        int piFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            piFlags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent content = PendingIntent.getActivity(this, 0, launch, piFlags);

        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(this, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(this);
        }
        builder.setContentTitle("航讯保持连接")
                .setContentText("锁屏来电需要保持连接，点此返回")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentIntent(content)
                .setOngoing(true)
                .setOnlyAlertOnce(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setVisibility(Notification.VISIBILITY_PUBLIC);
            builder.setPriority(Notification.PRIORITY_HIGH);
        }
        return builder.build();
    }

    /**
     * Flutter pauses Dart timers after onPause. Keep the isolate schedulable
     * and nudge IM from Dart so incoming-call UI can still be shown.
     */
    private void wakeFlutter() {
        try {
            final FlutterEngine engine =
                    FlutterEngineCache.getInstance().get(MainActivity.ENGINE_ID);
            if (engine == null) return;
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    engine.getLifecycleChannel().appIsInactive();
                } catch (Throwable ignored) {
                }
                try {
                    new MethodChannel(
                            engine.getDartExecutor().getBinaryMessenger(),
                            "top.hangxun.app/voip")
                            .invokeMethod("keepAliveTick", null);
                } catch (Throwable ignored) {
                }
            });
        } catch (Throwable ignored) {
        }
    }

    private void acquireLocks() {
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                if (wakeLock == null) {
                    wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "hangxun:im");
                    wakeLock.setReferenceCounted(false);
                }
                // Re-acquire each poke so OEM Doze cannot expire the lock.
                wakeLock.acquire(3 * 60 * 1000L);
            }
        } catch (Throwable t) {
            Log.e(TAG, "wake lock failed", t);
        }
        try {
            if (wifiLock == null || !wifiLock.isHeld()) {
                WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                if (wifi != null) {
                    wifiLock = wifi.createWifiLock(
                            WifiManager.WIFI_MODE_FULL_HIGH_PERF, "hangxun:im-wifi");
                    wifiLock.setReferenceCounted(false);
                    wifiLock.acquire();
                }
            }
        } catch (Throwable t) {
            Log.e(TAG, "wifi lock failed", t);
        }
    }

    private void releaseLocks() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        } catch (Throwable ignored) {
        }
        wakeLock = null;
        try {
            if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        } catch (Throwable ignored) {
        }
        wifiLock = null;
    }
}
