package com.example.my_agent_app

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import com.example.my_agent_app.native_tools.SystemSettings
// import com.example.my_agent_app.leap.LeapInferenceManager  // LEAP disabled temporarily
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val SYSTEM_CHANNEL = "com.myagent.tools/system"
    // private val LEAP_CHANNEL = "com.myagent.leap/inference"  // LEAP disabled temporarily
    private lateinit var systemSettings: SystemSettings
    // private val leapManager = LeapInferenceManager()  // LEAP disabled temporarily
    private val coroutineScope = CoroutineScope(Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        systemSettings = SystemSettings(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // System tools channel (existing)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableDnd" -> {
                    val duration = call.argument<Int>("duration") ?: 0
                    val success = systemSettings.enableDoNotDisturb(duration)
                    result.success(success)
                }
                "requestDndPermission" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "toggleFlashlight" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    val success = systemSettings.toggleFlashlight(enable)
                    result.success(success)
                }
                "setVolume" -> {
                    val volumePercent = call.argument<Int>("volumePercent") ?: 50
                    val success = systemSettings.setVolume(volumePercent)
                    result.success(success)
                }
                "setScreenBrightness" -> {
                    val brightnessPercent = call.argument<Int>("brightnessPercent") ?: 50
                    val success = systemSettings.setScreenBrightness(brightnessPercent)
                    result.success(success)
                }
                "toggleWifi" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    val success = systemSettings.toggleWifi(enable)
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // LEAP inference channel (disabled temporarily - uncomment when LEAP SDK is available)
        /*
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEAP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadModel" -> {
                    val bundlePath = call.argument<String>("bundlePath") ?: ""
                    coroutineScope.launch {
                        val success = leapManager.loadModel(bundlePath)
                        result.success(success)
                    }
                }
                "createConversation" -> {
                    val systemPrompt = call.argument<String>("systemPrompt") ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val functions = call.argument<List<Map<String, Any>>>("functions") ?: emptyList()
                    val success = leapManager.createConversation(systemPrompt, functions)
                    result.success(success)
                }
                "generateResponse" -> {
                    val userMessage = call.argument<String>("userMessage") ?: ""
                    val maxTokens = call.argument<Int>("maxTokens") ?: 300
                    val temperature = call.argument<Double>("temperature") ?: 0.2
                    val useHermesParser = call.argument<Boolean>("useHermesParser") ?: false
                    
                    coroutineScope.launch {
                        val response = leapManager.generateResponse(
                            userMessage,
                            maxTokens,
                            temperature,
                            useHermesParser
                        )
                        result.success(response)
                    }
                }
                "dispose" -> {
                    leapManager.dispose()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        */
    }
}
