package io.openim;

import android.os.Build;
import android.os.Bundle;

import androidx.core.splashscreen.SplashScreen;

import io.flutter.embedding.android.FlutterFragmentActivity;

public class MainActivity extends FlutterFragmentActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // Install before super so we can drop the Android 12+ system splash
        // immediately and reveal the full-bleed launch_background / Flutter splash.
        final SplashScreen splashScreen = SplashScreen.installSplashScreen(this);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener(splashScreenView -> splashScreenView.remove());
        }
        super.onCreate(savedInstanceState);
    }
}
