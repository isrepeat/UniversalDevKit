package com.isrepeat.androidappkit.update

internal object ApkUpdaterProtocol {
    const val packageName = "com.isrepeat.apkupdater"
    const val activityName = "com.isrepeat.apkupdater.UpdaterActivity"
    const val installPermission = "com.isrepeat.apkupdater.permission.INSTALL_UPDATE"
    const val installAction = "com.isrepeat.apkupdater.action.INSTALL_UPDATE"
    const val updateCompletedAction = "com.isrepeat.apkupdater.action.UPDATE_COMPLETED"
    const val targetPackageExtra = "target_package"
    const val traceExtra = "updater_trace"
    const val errorExtra = "update_error"
}