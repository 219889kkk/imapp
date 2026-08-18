package io.openim.flutter_openim_sdk.connectivity;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.Log;

public class VisibilityListener implements Application.ActivityLifecycleCallbacks {
    public void register(Activity activity) {
        if (null != activity) {
            activity.getApplication().registerActivityLifecycleCallbacks(this);
        }
    }

    public void unregisterReceiver(Activity activity) {
        if (null != activity) {
            activity.getApplication().unregisterActivityLifecycleCallbacks(this);
        }
    }


    @Override
    public void onActivityCreated(@NonNull Activity activity, @Nullable Bundle savedInstanceState) {
        Log.i("VisibilityListener", "onActivityCreated");
    }

    @Override
    public void onActivityStarted(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityStarted");
    }

    @Override
    public void onActivityResumed(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityResumed");
        HangxunImKeepAlivePoke.poke();
    }

    @Override
    public void onActivityPaused(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityPaused");
        // Do not report isBackground=true. HangXun has no Getui; lock
        // screen delivery is the websocket. Marking background makes
        // OpenIM queue messages until the user opens the app.
        HangxunImKeepAlivePoke.poke();
    }

    @Override
    public void onActivityStopped(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityStopped");
    }

    @Override
    public void onActivitySaveInstanceState(@NonNull Activity activity, @NonNull Bundle outState) {
        Log.i("VisibilityListener", "onActivitySaveInstanceState");
    }

    @Override
    public void onActivityDestroyed(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityDestroyed");
    }
}
