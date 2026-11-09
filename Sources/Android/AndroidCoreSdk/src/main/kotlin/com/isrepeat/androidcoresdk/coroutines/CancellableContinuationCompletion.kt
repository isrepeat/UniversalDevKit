package com.isrepeat.androidcoresdk.coroutines

//
// Изолирует Kotlin extension-вызовы завершения coroutine.
//
object CancellableContinuationCompletion {
    fun <Value> succeed(
        continuation: kotlinx.coroutines.CancellableContinuation<Value>,
        value: Value,
    ) {
        continuation.resumeWith(Result.success(value))
    }
    fun fail(
        continuation: kotlinx.coroutines.CancellableContinuation<*>,
        exception: Exception,
    ) {
        continuation.resumeWith(Result.failure(exception))
    }
}