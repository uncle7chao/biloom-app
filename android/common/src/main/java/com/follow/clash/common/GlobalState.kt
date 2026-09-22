package com.follow.clash.common

import android.app.ActivityManager
import android.app.Application
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

object GlobalState : CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {
    const val NOTIFICATION_CHANNEL = "BiLoom"
    const val NOTIFICATION_ID = 1
    private const val ANY_PID = 0
    private const val EVERY_EXIT_RECORD = 0

    val packageName: String
        get() = application.packageName

    val receiveBroadcastPermission: String
        get() = "$packageName.permission.RECEIVE_BROADCASTS"

    val application: Application
        get() = checkNotNull(appInstance) { "GlobalState is not initialized" }

    @Volatile
    private var appInstance: Application? = null

    fun init(application: Application) {
        appInstance = application
    }

    fun log(text: String) {
        Log.d("BiLoom", text)
    }

    // BiLoom: Firebase Crashlytics was removed from the fork (it also forced a
    // google-services.json whose package name breaks once applicationId changes).
    // The flag is kept as an inert switch so the shared-state plumbing is unchanged.
    @Suppress("UNUSED_PARAMETER")
    fun setCrashlytics(enable: Boolean) {
    }

    fun didCrashOnPreviousExecution(): Boolean {
        return false
    }

    fun lastExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val manager = application.getSystemService(ActivityManager::class.java) ?: return null
        val info = runCatching {
            manager.getHistoricalProcessExitReasons(
                application.packageName,
                ANY_PID,
                EVERY_EXIT_RECORD,
            )
        }.getOrNull()?.firstOrNull { it.processName == application.packageName } ?: return null
        return mapOf(
            "reason" to info.reason,
            "timestamp" to info.timestamp,
            "description" to info.description,
        )
    }
}
