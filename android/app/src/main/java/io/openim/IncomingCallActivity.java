package io.openim;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.lang.ref.WeakReference;

/**
 * Native lock-screen ringer. Flutter's GPU surface is often stale after a
 * long lock, so the incoming UI cannot depend on MainActivity.
 */
public class IncomingCallActivity extends Activity {
    private static WeakReference<IncomingCallActivity> current;

    static void finishIfShowing() {
        IncomingCallActivity a = current == null ? null : current.get();
        if (a != null && !a.isFinishing()) {
            a.finish();
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        current = new WeakReference<>(this);
        showOverLockscreen();
        setContentView(buildUi(getIntent()));
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        setContentView(buildUi(intent));
    }

    @Override
    protected void onDestroy() {
        if (current != null && current.get() == this) current.clear();
        stopVibrate();
        super.onDestroy();
    }

    private void showOverLockscreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true);
                setTurnScreenOn(true);
            }
            getWindow().addFlags(
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            | WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                            | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                            | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
        } catch (Throwable ignored) {
        }
    }

    private View buildUi(Intent intent) {
        String caller = intent != null ? intent.getStringExtra(HangxunIncomingCall.EXTRA_CALLER) : null;
        boolean video = intent != null && intent.getBooleanExtra(HangxunIncomingCall.EXTRA_VIDEO, false);
        if (caller == null || caller.isEmpty()) caller = "来电";

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setBackgroundColor(0xFF095C37);
        int pad = dp(32);
        root.setPadding(pad, dp(80), pad, pad);

        TextView hint = new TextView(this);
        hint.setText(video ? "视频来电" : "语音来电");
        hint.setTextColor(0xCCFFFFFF);
        hint.setTextSize(16);
        hint.setGravity(Gravity.CENTER);
        root.addView(hint);

        TextView name = new TextView(this);
        name.setText(caller);
        name.setTextColor(Color.WHITE);
        name.setTextSize(32);
        name.setTypeface(Typeface.DEFAULT_BOLD);
        name.setGravity(Gravity.CENTER);
        name.setPadding(0, dp(16), 0, dp(48));
        root.addView(name);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams row =
                new LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT);
        buttons.setLayoutParams(row);

        Button reject = new Button(this);
        reject.setText("拒绝");
        reject.setTextColor(Color.WHITE);
        reject.setBackgroundColor(0xFFE53935);
        reject.setOnClickListener(v -> {
            HangxunIncomingCall.reject(getApplicationContext(), getIntent());
            finish();
        });
        LinearLayout.LayoutParams lp =
                new LinearLayout.LayoutParams(0, dp(52), 1f);
        lp.setMargins(0, 0, dp(12), 0);
        reject.setLayoutParams(lp);
        buttons.addView(reject);

        Button accept = new Button(this);
        accept.setText("接听");
        accept.setTextColor(Color.WHITE);
        accept.setBackgroundColor(0xFF43A047);
        accept.setOnClickListener(v -> {
            HangxunIncomingCall.accept(getApplicationContext(), getIntent());
            finish();
        });
        LinearLayout.LayoutParams lp2 =
                new LinearLayout.LayoutParams(0, dp(52), 1f);
        lp2.setMargins(dp(12), 0, 0, 0);
        accept.setLayoutParams(lp2);
        buttons.addView(accept);

        root.addView(buttons);
        return root;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private void stopVibrate() {
        try {
            Vibrator vib;
            if (Build.VERSION.SDK_INT >= 31) {
                VibratorManager vm =
                        (VibratorManager) getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
                vib = vm != null ? vm.getDefaultVibrator() : null;
            } else {
                vib = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
            }
            if (vib != null) vib.cancel();
        } catch (Throwable ignored) {
        }
    }
}
