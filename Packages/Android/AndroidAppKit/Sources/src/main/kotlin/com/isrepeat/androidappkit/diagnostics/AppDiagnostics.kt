package com.isrepeat.androidappkit.diagnostics

//
// Диагностика пакетов и APK без знания конкретного приложения или native-рендерера.
//
class AppDiagnostics(private val logger: (String) -> Unit) {
    fun logArchive(context: android.content.Context, archive: java.io.File) {
        val packageInfo = context.packageManager.getPackageArchiveInfo(archive.path, 0)
        logger(
            if (packageInfo == null) {
                "APK metadata unavailable: file=${archive.name}, bytes=${archive.length()}"
            } else {
                "APK package=${packageInfo.packageName}, version=${packageInfo.versionName}, " +
                    "code=${versionCode(packageInfo)}, bytes=${archive.length()}"
            },
        )
    }

    fun logUpdaterAccess(
        context: android.content.Context,
        updaterPackage: String,
        updaterPermission: String,
    ) {
        val packageManager = context.packageManager
        logger(
            "updater=$updaterPackage, signatures=" +
                packageManager.checkSignatures(context.packageName, updaterPackage) +
                ", permission=${packageManager.checkPermission(updaterPermission, context.packageName)}",
        )
    }

    @Suppress("DEPRECATION")
    private fun versionCode(packageInfo: android.content.pm.PackageInfo): Long =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            packageInfo.versionCode.toLong()
        }
}