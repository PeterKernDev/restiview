package com.restiview.app

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter 3.22+ enables edge-to-edge by default, which causes the
        // Android 3-button navigation bar to overlap app content. Re-applying
        // decorFitsSystemWindows = true restores the previous behaviour where
        // the nav bar sits below the app rather than on top of it.
        WindowCompat.setDecorFitsSystemWindows(window, true)
    }
}
