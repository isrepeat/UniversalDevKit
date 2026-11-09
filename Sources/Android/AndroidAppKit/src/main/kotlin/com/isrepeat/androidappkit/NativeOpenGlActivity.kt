package com.isrepeat.androidappkit

//
// Прозрачность Activity дополнительно задаётся темой в манифесте приложения.
//
abstract class NativeOpenGlActivity : androidx.activity.ComponentActivity() {
    protected open val translucentSurface: Boolean = false

    private lateinit var surface: RenderSurface
    private var handle = 0L
    private var closed = false

    //
    // androidx.activity.ComponentActivity
    //
    final override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handle = createNativeSession()
        if (handle == 0L) {
            throw IllegalStateException("Native session creation failed")
        }
        surface = RenderSurface()
        onPageCreated(savedInstanceState)
        setContentView(surface)
        onBackPressedDispatcher.addCallback(this, object : androidx.activity.OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (!onBackRequested()) {
                    withNativeSession { session ->
                        if (!nativeBack(session)) {
                            runOnUiThread {
                                if (!closed && !isFinishing) {
                                    finish()
                                }
                            }
                        }
                    }
                }
            }
        })
        onPageIntent(intent)
    }

    final override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        onPageIntent(intent)
    }

    final override fun onResume() {
        super.onResume()
        surface.onResume()
        onPageResumed()
    }

    final override fun onPause() {
        onPagePaused()
        // Освобождаем GPU-ресурсы до остановки GL-потока и потери контекста.
        runOnRenderThreadAndWait { nativeReleaseSurface(handle) }
        surface.onPause()
        super.onPause()
    }

    final override fun onDestroy() {
        closed = true
        try {
            onPageDestroyed()
        } finally {
            try {
                // GLSurfaceView обрабатывает очередь событий и в состоянии pause.
                runOnRenderThreadAndWait {
                    nativeDestroy(handle)
                    handle = 0L
                }
            } finally {
                super.onDestroy()
            }
        }
    }

    //
    // Interface
    //
    protected abstract fun createNativeSession(): Long
    protected abstract fun nativeDestroy(handle: Long)
    protected abstract fun nativeSurface(handle: Long, width: Int, height: Int)
    protected abstract fun nativeReleaseSurface(handle: Long)
    protected abstract fun nativeRender(handle: Long)
    protected abstract fun nativePointer(handle: Long, action: Int, x: Float, y: Float)
    protected abstract fun nativeBack(handle: Long): Boolean

    protected open fun onPageCreated(savedInstanceState: android.os.Bundle?) {}
    protected open fun onPageResumed() {}
    protected open fun onPagePaused() {}
    protected open fun onPageIntent(intent: android.content.Intent) {}
    protected open fun onPageDestroyed() {}

    // true означает, что приложение обработало событие и native-вызов не нужен.
    protected open fun onBackRequested(): Boolean = false
    protected open fun onPageTouchEvent(event: android.view.MotionEvent): Boolean = false

    //
    // Internal
    //
    // Вызывается на UI-потоке; обработчик получает сессию только на GL-потоке.
    protected fun withNativeSession(action: (Long) -> Unit) {
        if (closed) {
            return
        }
        surface.queueEvent {
            if (handle != 0L) {
                action(handle)
            }
        }
    }

    private fun runOnRenderThreadAndWait(action: () -> Unit) {
        val task = java.util.concurrent.FutureTask<Unit> {
            action()
        }
        surface.queueEvent(task)
        task.get()
    }


    private inner class RenderSurface
        : android.opengl.GLSurfaceView(this@NativeOpenGlActivity)
        , android.opengl.GLSurfaceView.Renderer {

        init {
            setEGLContextClientVersion(3)
            if (translucentSurface) {
                setEGLConfigChooser(8, 8, 8, 8, 0, 0)
                holder.setFormat(android.graphics.PixelFormat.TRANSLUCENT)
                setZOrderOnTop(true)
            }
            setRenderer(this)
        }

        override fun onSurfaceCreated(
            gl: javax.microedition.khronos.opengles.GL10?,
            config: javax.microedition.khronos.egl.EGLConfig?,
        ) {
            if (translucentSurface) {
                val alphaBits = IntArray(1)
                android.opengl.GLES30.glGetIntegerv(android.opengl.GLES30.GL_ALPHA_BITS, alphaBits, 0)
                if (alphaBits[0] < 8) {
                    throw IllegalStateException("The OpenGLES window requires an 8-bit alpha channel")
                }
                androidappkit.diagnostics.sharedLogger().log("OpenGLES framebuffer alpha bits: ${alphaBits[0]}")
            }
        }

        override fun onSurfaceChanged(gl: javax.microedition.khronos.opengles.GL10?, width: Int, height: Int) {
            if (handle != 0L) {
                nativeSurface(handle, width, height)
            }
        }

        override fun onDrawFrame(gl: javax.microedition.khronos.opengles.GL10?) {
            if (handle != 0L) {
                nativeRender(handle)
            }
        }

        override fun onTouchEvent(event: android.view.MotionEvent): Boolean {
            if (!onPageTouchEvent(event)) {
                val action = event.actionMasked
                val x = event.x
                val y = event.y
                withNativeSession { session -> nativePointer(session, action, x, y) }
            }
            return true
        }
    }
}