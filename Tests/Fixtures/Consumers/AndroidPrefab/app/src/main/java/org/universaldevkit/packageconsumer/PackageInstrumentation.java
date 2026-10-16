package org.universaldevkit.packageconsumer;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;

public final class PackageInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            int status = NativeBridge.verify();
            result.putString("UDK_RESULT", status == 0 ? "PASS" : "FAIL: " + status);
            finish(status == 0 ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        } catch (Throwable error) {
            result.putString("UDK_RESULT", "FAIL: " + error.toString());
            finish(Activity.RESULT_CANCELED, result);
        }
    }
}