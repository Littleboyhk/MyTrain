package com.mytrain.my_train

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellIdentityNr
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Serving-cell identity for the crowdsourced cell-tower dataset (Phase 2).
 *
 * WHY NATIVE. No maintained Flutter plugin covers serving-cell identity — the
 * `telephony` package states it is no longer actively maintained — so this is the
 * platform-channel fallback the feature brief specified. The exposed surface is
 * one method returning a flat map, which keeps the native side small enough to
 * read in one sitting.
 *
 * FAILS SOFT, ALWAYS. Every path returns `null` rather than raising: missing
 * permission, no SIM, an emulator with no radio, or an unsupported API level. The
 * Dart side treats `null` as "nothing to record" and offline positioning is
 * completely unaffected.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.mytrain.my_train/cell_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getServingCell" -> result.success(readServingCell())
                else -> result.notImplemented()
            }
        }
    }

    private fun hasLocationPermission(): Boolean {
        // getAllCellInfo() requires a location grant; without it Android returns
        // an empty list rather than throwing, so this check exists to make the
        // reason visible instead of looking like "no towers nearby".
        //
        // checkCallingOrSelfPermission rather than ContextCompat: it is a plain
        // Context method present on every API level, so the native side needs no
        // androidx dependency of its own.
        val fine = checkCallingOrSelfPermission(
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = checkCallingOrSelfPermission(
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun readServingCell(): Map<String, Any?>? {
        if (!hasLocationPermission()) return null

        val telephony =
            getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                ?: return null

        val cells: List<CellInfo> = try {
            @Suppress("DEPRECATION")
            telephony.allCellInfo ?: return null
        } catch (e: SecurityException) {
            return null
        } catch (e: Exception) {
            return null
        }

        // Prefer the registered (serving) cell; neighbours carry identity too but
        // are not where the handset actually is attached.
        val serving = cells.firstOrNull { it.isRegistered } ?: return null

        return when (serving) {
            is CellInfoLte -> {
                val id = serving.cellIdentity
                mapOf(
                    "radioType" to "lte",
                    "cellId" to id.ci,
                    "lac" to id.tac,
                    "mcc" to mccOf(id.mccString, @Suppress("DEPRECATION") id.mcc),
                    "mnc" to mncOf(id.mncString, @Suppress("DEPRECATION") id.mnc),
                    "signalDbm" to serving.cellSignalStrength.dbm
                )
            }

            is CellInfoGsm -> {
                val id = serving.cellIdentity
                mapOf(
                    "radioType" to "gsm",
                    "cellId" to id.cid,
                    "lac" to id.lac,
                    "mcc" to mccOf(id.mccString, @Suppress("DEPRECATION") id.mcc),
                    "mnc" to mncOf(id.mncString, @Suppress("DEPRECATION") id.mnc),
                    "signalDbm" to serving.cellSignalStrength.dbm
                )
            }

            is CellInfoWcdma -> {
                val id = serving.cellIdentity
                mapOf(
                    "radioType" to "wcdma",
                    "cellId" to id.cid,
                    "lac" to id.lac,
                    "mcc" to mccOf(id.mccString, @Suppress("DEPRECATION") id.mcc),
                    "mnc" to mncOf(id.mncString, @Suppress("DEPRECATION") id.mnc),
                    "signalDbm" to serving.cellSignalStrength.dbm
                )
            }

            else -> {
                // 5G arrived in API 29; guard so older devices don't touch the
                // class at all.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                    serving is CellInfoNr
                ) {
                    val id = serving.cellIdentity as? CellIdentityNr ?: return null
                    mapOf(
                        "radioType" to "nr",
                        // NCI is a Long; Dart reads it back through int.tryParse.
                        "cellId" to id.nci.toString(),
                        "lac" to id.tac,
                        "mcc" to id.mccString?.toIntOrNull(),
                        "mnc" to id.mncString?.toIntOrNull(),
                        "signalDbm" to serving.cellSignalStrength.dbm
                    )
                } else {
                    null
                }
            }
        }
    }

    /** Prefer the string form (API 28+), falling back to the deprecated int. */
    private fun mccOf(text: String?, legacy: Int): Int? =
        text?.toIntOrNull() ?: legacy.takeIf { it != Int.MAX_VALUE }

    private fun mncOf(text: String?, legacy: Int): Int? =
        text?.toIntOrNull() ?: legacy.takeIf { it != Int.MAX_VALUE }
}
