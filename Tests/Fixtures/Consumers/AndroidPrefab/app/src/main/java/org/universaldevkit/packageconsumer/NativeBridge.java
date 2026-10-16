package org.universaldevkit.packageconsumer;

final class NativeBridge {
    static { System.loadLibrary("udk_android_consumer"); }
    static native int verify();
}