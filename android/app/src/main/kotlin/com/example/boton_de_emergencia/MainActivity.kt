package com.teckali.boton_de_emergencia

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.teckali.system/packages"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPackage" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.error("ARG_ERROR", "packageName requerido", null)
                        return@setMethodCallHandler
                    }
                    result.success(hasPackage(packageName))
                }
                "checkServices" -> {
                    val hasGms = hasPackage("com.google.android.gms")
                    // Huawei ID / HMS Core
                    val hasHmsId = hasPackage("com.huawei.hwid")
                    val hasHmsCore = hasPackage("com.huawei.hms")
                    result.success(
                        mapOf(
                            "gms" to hasGms,
                            "hmsId" to hasHmsId,
                            "hmsCore" to hasHmsCore
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPackage(pkg: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Android 13+ → API nueva con PackageInfoFlags
                packageManager.getPackageInfo(
                    pkg,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                // Android <= 12 → API vieja (deprecated pero compatible)
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(pkg, 0)
            }
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        } catch (e: Exception) {
            // Por si acaso algo más raro pasa
            false
        }
    }
}