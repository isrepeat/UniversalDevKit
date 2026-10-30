package com.isrepeat.androidappkit.update

data class GoogleDriveUpdateConfiguration(
    val driveFolderPath: List<String>,
    val apkNamePattern: Regex,
    val versionCodeFromName: (MatchResult) -> Long,
    val updaterPackage: String = ApkUpdaterProtocol.packageName,
    val updaterActivity: String = ApkUpdaterProtocol.activityName,
    val updaterPermission: String = ApkUpdaterProtocol.installPermission,
    val updaterAction: String = ApkUpdaterProtocol.installAction,
    val targetPackageExtra: String = ApkUpdaterProtocol.targetPackageExtra,
    val confirmSameVersionInUpdater: Boolean = false,
)