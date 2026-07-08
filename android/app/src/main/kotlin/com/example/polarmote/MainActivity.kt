package com.example.Polarmote

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pendingApkToInstall: String? = null
    private val requestUnknownAppSourcesCode = 8612
    private val transferForegroundChannel = "Polarmote/transfer_foreground"
    private val sshForegroundChannel = "Polarmote/ssh_foreground"
    private val startupGuardChannel = "Polarmote/startup_guard"

    private fun startApkInstaller(filePath: String): Boolean {
        val file = File(filePath)
        if (!file.exists()) return false

        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != requestUnknownAppSourcesCode) return

        val filePath = pendingApkToInstall ?: return
        val file = File(filePath)
        if (!file.exists()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canInstall = packageManager.canRequestPackageInstalls()
            if (!canInstall) return
        }

        if (startApkInstaller(filePath)) {
            pendingApkToInstall = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "note_sync/multicast_lock").setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    try {
                        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        if (multicastLock == null) {
                            multicastLock = wifi.createMulticastLock("note_sync_multicast_lock").apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (multicastLock?.isHeld != true) {
                            multicastLock?.acquire()
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("acquire_failed", e.message, null)
                    }
                }
                "release" -> {
                    try {
                        if (multicastLock?.isHeld == true) {
                            multicastLock?.release()
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("release_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.note_770/install").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.success(
                            mapOf(
                                "started" to false,
                                "permissionRequired" to false,
                                "reason" to "missing_file_path",
                            )
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.success(
                                mapOf(
                                    "started" to false,
                                    "permissionRequired" to false,
                                    "reason" to "file_not_found",
                                )
                            )
                            return@setMethodCallHandler
                        }

                        // Android 8.0+ needs "Install unknown apps" permission per-app.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val canInstall = packageManager.canRequestPackageInstalls()
                            if (!canInstall) {
                                pendingApkToInstall = filePath
                                val intent =
                                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, requestUnknownAppSourcesCode)
                                result.success(
                                    mapOf(
                                        "started" to false,
                                        "permissionRequired" to true,
                                        "reason" to "permission_required",
                                    )
                                )
                                return@setMethodCallHandler
                            }
                        }

                        val started = startApkInstaller(filePath)
                        result.success(
                            mapOf(
                                "started" to started,
                                "permissionRequired" to false,
                                "reason" to if (started) null else "start_failed",
                            )
                        )
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, transferForegroundChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val title = call.argument<String>("title")
                        TransferForegroundService.start(applicationContext, title)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("start_failed", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        TransferForegroundService.stop(applicationContext)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("stop_failed", e.message, null)
                    }
                }
                "isRunning" -> result.success(TransferForegroundService.isRunning)
                "updateProgress" -> {
                    try {
                        val title = call.argument<String>("title")
                        val progressPermille = call.argument<Int>("progressPermille")
                        val progressPercent = call.argument<Int>("progressPercent")
                        val indeterminate = call.argument<Boolean>("indeterminate")
                        val activeCount = call.argument<Int>("activeCount")
                        TransferForegroundService.updateProgress(
                            context = applicationContext,
                            title = title,
                            progressPermille = progressPermille,
                            progressPercent = progressPercent,
                            indeterminate = indeterminate,
                            activeCount = activeCount,
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("update_progress_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sshForegroundChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val title = call.argument<String>("title")
                        SshForegroundService.start(applicationContext, title)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("start_failed", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        SshForegroundService.stop(applicationContext)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("stop_failed", e.message, null)
                    }
                }
                "isRunning" -> result.success(SshForegroundService.isRunning)
                "updateState" -> {
                    try {
                        val title = call.argument<String>("title")
                        val activeCount = call.argument<Int>("activeCount")
                        SshForegroundService.updateState(
                            context = applicationContext,
                            title = title,
                            activeCount = activeCount,
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("update_state_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, startupGuardChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        val powerManager =
                            applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val ignoring = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                        result.success(ignoring)
                    } catch (e: Exception) {
                        result.error("check_battery_optimization_failed", e.message, null)
                    }
                }

                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val powerManager =
                                applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                            val ignoring = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                            if (!ignoring) {
                                val intent =
                                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                        data = Uri.parse("package:$packageName")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                startActivity(intent)
                            }
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("request_battery_optimization_failed", e.message, null)
                    }
                }

                "openBatteryOptimizationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("open_battery_settings_failed", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
