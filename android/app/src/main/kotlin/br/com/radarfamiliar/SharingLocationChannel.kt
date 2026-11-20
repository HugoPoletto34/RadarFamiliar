package br.com.radarfamiliar

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Liga e desliga o serviço de localização a partir do Dart.
class SharingLocationChannel(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    SharingLocationService.start(context)
                    result.success(null)
                }
                "stop" -> {
                    SharingLocationService.stop(context)
                    result.success(null)
                }
                // No Android o serviço em primeiro plano já segura o processo.
                "beginUpload", "endUpload" -> result.success(null)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("location", e.message ?: "Falha ao manter a localização.", null)
        }
    }

    companion object {
        const val NAME = "br.com.radarfamiliar/location_share"
    }
}
