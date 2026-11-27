package com.nyatet.nyatet

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Jembatan REL-03: membaca nama paket + sertifikat sebuah APK dan
 * membandingkannya dengan aplikasi yang terpasang, lalu membuka layar
 * pemasangan Android. Verifikasi ada di sisi native supaya APK yang akan
 * dipasang tidak bisa lolos hanya dengan memalsukan data di Dart.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "nyatet/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inspectApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path wajib", null)
                        } else {
                            try {
                                result.success(inspectApk(path))
                            } catch (e: Exception) {
                                result.error("INSPECT_FAILED", e.message, null)
                            }
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path wajib", null)
                        } else {
                            try {
                                result.success(openInstaller(path))
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun inspectApk(path: String): Map<String, Any?> {
        val file = File(path)
        require(file.exists()) { "Berkas APK tidak ada" }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        // APK arsip dibaca lewat getPackageArchiveInfo; getPackageInfo(path)
        // hanya untuk paket terpasang dan melempar NameNotFoundException.
        val apkInfo: PackageInfo = packageManager.getPackageArchiveInfo(
            file.absolutePath,
            flags,
        ) ?: throw IllegalStateException("APK tidak bisa dibaca")
        // Sebagian versi Android butuh sourceDir diisi agar signingInfo ada.
        apkInfo.applicationInfo?.apply {
            sourceDir = file.absolutePath
            publicSourceDir = file.absolutePath
        }
        val installedInfo: PackageInfo = packageManager.getPackageInfo(
            packageName,
            flags,
        )

        return mapOf(
            "packageName" to apkInfo.packageName,
            "installedPackageName" to installedInfo.packageName,
            "signatureSha256" to signatureDigest(apkInfo),
            "installedSignatureSha256" to signatureDigest(installedInfo),
        )
    }

    private fun signatureDigest(info: PackageInfo): String {
        val signatures: Array<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo
                ?: return ""
            if (signing.hasMultipleSigners()) {
                signing.apkContentsSigners
            } else {
                signing.signingCertificateHistory
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures ?: return ""
        }
        if (signatures.isEmpty()) return ""
        val digest = MessageDigest.getInstance("SHA-256")
        // Sertifikat pertama cukup: kunci rilis Nyatet tunggal.
        return digest.digest(signatures.first().toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    /** Intent pemasangan sistem — user tetap harus menyetujui di layar Android. */
    private fun openInstaller(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return true
    }
}
