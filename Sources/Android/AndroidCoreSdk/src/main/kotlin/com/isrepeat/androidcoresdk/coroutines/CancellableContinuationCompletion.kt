package com.isrepeat.androidcoresdk.coroutines

//
// Encapsulate Kotlin extension calls that complete the coroutine.
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