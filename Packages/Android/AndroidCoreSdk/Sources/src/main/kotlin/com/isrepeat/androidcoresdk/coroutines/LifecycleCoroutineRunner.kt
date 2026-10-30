package com.isrepeat.androidcoresdk.coroutines

import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

//
// Связывает coroutine с жизненным циклом владельца, не раскрывая AndroidX в вызывающем коде.
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