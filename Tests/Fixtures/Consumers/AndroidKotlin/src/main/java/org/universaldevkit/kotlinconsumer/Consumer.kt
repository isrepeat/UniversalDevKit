package org.universaldevkit.kotlinconsumer

import com.isrepeat.androidappkit.AppIdentity
import com.isrepeat.androidappkit.diagnostics.AppKitLogger
import com.isrepeat.androidcoresdk.nativeui.NativeRenderHost

class Consumer(val host: NativeRenderHost) {
    val identity = AppIdentity("Consumer", "consumer")
    val logger = AppKitLogger { host.log(it) }
}