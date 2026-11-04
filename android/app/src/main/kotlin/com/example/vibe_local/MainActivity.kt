package com.example.vibe_local

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.min

class MainActivity : AudioServiceActivity() {

    private var visualizer: Visualizer? = null
    private var liveSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var targetBands: Int = 48

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal para el Espectro en Vivo (Visualizer API de Android)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vibe/spectrum").setMethodCallHandler { call, result ->
            when (call.method) {
                "startLive" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    targetBands = call.argument<Int>("bands") ?: 48
                    startVisualizer(sessionId)
                    result.success(true)
                }
                "stopLive" -> {
                    stopVisualizer()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "vibe/spectrum/live").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    liveSink = events
                }

                override fun onCancel(arguments: Any?) {
                    liveSink = null
                }
            }
        )

        // Canal para actualizar el Widget de la pantalla de inicio
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vibe/widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val title = call.argument<String>("title") ?: "Vibe Local"
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val coverPath = call.argument<String>("coverPath")

                    VibeWidgetProvider.updateAll(applicationContext, title, artist, isPlaying, coverPath)
                    result.success(true)
                }
                "ready" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVisualizer(sessionId: Int) {
        stopVisualizer()
        try {
            val captureSize = Visualizer.getCaptureSizeRange()[1] // Máxima resolución FFT disponible
            val viz = Visualizer(sessionId).apply {
                this.captureSize = min(captureSize, 512)
                setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(viz: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}

                    override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                        if (fft == null || liveSink == null) return
                        val bands = processFftToBands(fft, targetBands)
                        mainHandler.post {
                            liveSink?.success(bands)
                        }
                    }
                }, Visualizer.getMaxCaptureRate() / 2, false, true)
                enabled = true
            }
            visualizer = viz
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {}
        visualizer = null
    }

    /**
     * Convierte los coeficientes crudos de la FFT en un array de magnitudes normalizadas (0.0 .. 1.0)
     * distribuidas en frecuencias bajas, medias y agudas con escala logarítmica para máxima fidelidad visual.
     */
    private fun processFftToBands(fft: ByteArray, bandCount: Int): FloatArray {
        val n = fft.size / 2
        val magnitudes = FloatArray(n)

        // La componente DC es fft[0], Nyquist es fft[1]
        magnitudes[0] = Math.abs(fft[0].toFloat())
        for (k in 1 until n) {
            val r = fft[2 * k].toFloat()
            val i = fft[2 * k + 1].toFloat()
            magnitudes[k] = hypot(r, i)
        }

        val out = FloatArray(bandCount)
        val minFreq = 1.0
        val maxFreq = n.toDouble()

        for (b in 0 until bandCount) {
            // Escala logarítmica (más resolución en bajos y medios)
            val fLow = (minFreq * Math.pow(maxFreq / minFreq, b.toDouble() / bandCount)).toInt().coerceIn(0, n - 1)
            val fHigh = (minFreq * Math.pow(maxFreq / minFreq, (b + 1).toDouble() / bandCount)).toInt().coerceIn(fLow + 1, n)

            var sum = 0f
            var count = 0
            for (k in fLow until fHigh) {
                sum += magnitudes[k]
                count++
            }
            val avg = if (count > 0) sum / count else magnitudes[fLow]
            // Normalizar a decibelios aproximados
            val normalized = (ln((avg + 1f).toDouble()) / 4.8).toFloat().coerceIn(0.05f, 1.0f)
            out[b] = normalized
        }
        return out
    }

    override fun onDestroy() {
        stopVisualizer()
        super.onDestroy()
    }
}
