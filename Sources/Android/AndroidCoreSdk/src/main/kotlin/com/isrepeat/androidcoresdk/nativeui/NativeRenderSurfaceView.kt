package com.isrepeat.androidcoresdk.nativeui

//
// Общий адаптер SurfaceView, оставляющий JNI-детали в реализации NativeRenderHost.
//
open class NativeRenderSurfaceView(
    context: android.content.Context,
    private val host: NativeRenderHost,
) : android.view.SurfaceView(context), android.view.SurfaceHolder.Callback, android.view.Choreographer.FrameCallback {
    private var isRendering = false
    private var hasRenderedFirstFrame = false

    init {
        holder.addCallback(this)
        setOnTouchListener { _, event -> host.onTouch(event.actionMasked, event.x, event.y); true }
    }

    override fun surfaceCreated(holder: android.view.SurfaceHolder) = host.log("SurfaceView.surfaceCreated")

    override fun surfaceChanged(holder: android.view.SurfaceHolder, format: Int, width: Int, height: Int) {
        host.log("SurfaceView.surfaceChanged started: ${width}x$height")
        host.onSurfaceChanged(holder.surface, width, height)
        host.log("SurfaceView.surfaceChanged completed")
        isRendering = true
        android.view.Choreographer.getInstance().postFrameCallback(this)
    }

    override fun surfaceDestroyed(holder: android.view.SurfaceHolder) {
        isRendering = false
        host.log("SurfaceView.surfaceDestroyed started")
        host.onSurfaceDestroyed()
        host.log("SurfaceView.surfaceDestroyed completed")
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!isRendering) return
        if (!hasRenderedFirstFrame) host.log("SurfaceView.firstFrame started")
        host.render()
        if (!hasRenderedFirstFrame) { hasRenderedFirstFrame = true; host.log("SurfaceView.firstFrame completed") }
        android.view.Choreographer.getInstance().postFrameCallback(this)
    }
}