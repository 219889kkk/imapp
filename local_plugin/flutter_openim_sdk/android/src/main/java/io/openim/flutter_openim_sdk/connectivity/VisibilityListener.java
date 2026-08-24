package io.openim.flutter_openim_sdk.connectivity;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;

import io.flutter.Log;

public class VisibilityListener implements Application.ActivityLifecycleCallbacks {
    public void register(Activity activity) {
        if (null != activity) {
            activity.getApplication().registerActivityLifecycleCallbacks(this);
            if (activity instanceof LifecycleOwner) {
                Lifecycle.State state =
                        ((LifecycleOwner) activity).getLifecycle().getCurrentState();
                if (state.isAtLeast(Lifecycle.State.STARTED)) {
                    HangxunImKeepAlivePoke.onActivityStarted();
                }
            }
        }
    }

    public void unregisterReceiver(Activity activity) {
        if (null != activity) {
            activity.getApplication().unregisterActivityLifecycleCallbacks(this);
            if (activity instanceof LifecycleOwner) {
                Lifecycle.State state =
                        ((LifecycleOwner) activity).getLifecycle().getCurrentState();
                if (state.isAtLeast(Lifecycle.State.STARTED)) {
                    HangxunImKeepAlivePoke.onActivityStopped();
                }
            }
        }
    }


    @Override
    public void onActivityCreated(@NonNull Activity activity, @Nullable Bundle savedInstanceState) {
        Log.i("VisibilityListener", "onActivityCreated");
    }

    @Override
    public void onActivityStarted(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityStarted");
        if (isNativeCallUi(activity)) return;
        HangxunImKeepAlivePoke.onActivityStarted();
    }

    @Override
    public void onActivityResumed(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityResumed");
    }

    @Override
    public void onActivityPaused(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityPaused");
    }

    @Override
    public void onActivityStopped(@NonNull Activity activity) {
        Log.i("VisibilityListener", "onActivityStopped");
        if (isNativeCallUi(activity)) return;
        HangxunImKeepAlivePoke.onActivityStopped();
    }

    private static boolean isNativeCallUi(Activity activity) {
        return activity.getClass().getName().contains("IncomingCallActivity");
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
