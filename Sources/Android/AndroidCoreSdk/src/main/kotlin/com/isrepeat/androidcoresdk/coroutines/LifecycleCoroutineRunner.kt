package com.isrepeat.androidcoresdk.coroutines

import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

//
// Bind the coroutine to its owner lifecycle without exposing AndroidX to callers.
//
object LifecycleCoroutineRunner {
    fun launch(
        owner: androidx.lifecycle.LifecycleOwner,
        action: suspend () -> Unit,
    ) {
        owner.lifecycleScope.launch {
            action()
        }
    }
}