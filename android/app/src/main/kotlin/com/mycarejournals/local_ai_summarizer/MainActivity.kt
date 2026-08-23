package com.mycarejournals.local_ai_summarizer

import android.os.Build
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.mycarejournals.local_ai_summarizer/nano"
    private val AICORE_PACKAGE = "com.google.android.aicore"
    private val coroutineScope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNanoAvailable" -> {
                    coroutineScope.launch {
                        try {
                            val client = Generation.getClient()
                            val status = withContext(Dispatchers.IO) {
                                client.checkStatus()
                            }
                            result.success(status == FeatureStatus.AVAILABLE)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "getAiCoreVersion" -> {
                    // Records which AICore build served the request, so results from
                    // different devices or dates can be compared meaningfully.
                    try {
                        val info = packageManager.getPackageInfo(AICORE_PACKAGE, 0)
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            info.versionCode.toLong()
                        }
                        val versionName = info.versionName ?: "unknown"
                        result.success("$versionName ($versionCode)")
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "generateNanoText" -> {
                    val prompt = call.argument<String>("prompt") ?: ""
                    val temperature = call.argument<Double>("temperature")?.toFloat() ?: 0.2f
                    val topK = call.argument<Int>("topK") ?: 40

                    if (prompt.isEmpty()) {
                        result.error("INVALID_PROMPT", "Prompt cannot be empty", null)
                        return@setMethodCallHandler
                    }

                    coroutineScope.launch {
                        try {
                            val client = Generation.getClient()
                            val request = generateContentRequest(TextPart(prompt)) {
                                this.temperature = temperature
                                this.topK = topK
                            }
                            val response = withContext(Dispatchers.IO) {
                                client.generateContent(request)
                            }
                            val outputText = response.candidates.firstOrNull()?.text ?: ""
                            result.success(outputText)
                        } catch (e: Exception) {
                            result.error("INFERENCE_ERROR", e.localizedMessage, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}