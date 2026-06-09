package com.adoetz.adoetzgpt

import android.content.Intent
import android.os.Build
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val liveAudioChannel = "adoetzgpt/live_audio"
    private val liveForegroundChannel = "adoetzgpt/live_foreground"
    private var audioTrack: AudioTrack? = null
    private var audioExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            liveAudioChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 24000
                    startPcmPlayback(sampleRate)
                    result.success(null)
                }
                "play" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.error("bad_args", "PCM payload missing.", null)
                    } else {
                        audioExecutor.execute {
                            audioTrack?.write(bytes, 0, bytes.size)
                        }
                        result.success(null)
                    }
                }
                "stop" -> {
                    stopPcmPlayback()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            liveForegroundChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, LiveForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, LiveForegroundService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startPcmPlayback(sampleRate: Int) {
        stopPcmPlayback()
        if (audioExecutor.isShutdown) {
            audioExecutor = Executors.newSingleThreadExecutor()
        }
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = maxOf(minBuffer, sampleRate * 2)
        audioTrack = AudioTrack(
            AudioManager.STREAM_MUSIC,
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
            AudioTrack.MODE_STREAM
        )
        audioTrack?.play()
    }

    private fun stopPcmPlayback() {
        val track = audioTrack
        audioTrack = null
        try {
            track?.pause()
            track?.flush()
            track?.release()
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        stopPcmPlayback()
        audioExecutor.shutdownNow()
        super.onDestroy()
    }
}
