package org.universaldevkit.testpackages.consumer

import android.app.Activity
import android.os.Bundle
import org.universaldevkit.testpackages.appkit.AppKit
import org.universaldevkit.testpackages.core.Core

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(AppKit.value() == 42 && Core.value() == 42)
        android.util.Log.i("UdkPackagePackageDelivery", "PASS")
    }
}