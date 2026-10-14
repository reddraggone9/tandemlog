package com.reddraggone9.tandemlog

import android.app.Activity
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Two constant destinations. Dart owns setup, draft guards and navigation. */
internal class SectionShortcuts(private val activity: Activity) {
    private var channel: MethodChannel? = null
    private var initialCaptured = false
    private var sequence = 0L
    private var pending: Map<String, Any>? = null

    fun configure(engine: FlutterEngine, restoringActivity: Boolean) {
        // The original shortcut action survives Android activity restoration.
        // Only a fresh launch is an explicit navigation request.
        if (!initialCaptured) {
            initialCaptured = true
            if (!restoringActivity) receive(activity.intent, notify = false)
        }
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "tandemlog/sections").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                if (call.method == "takeInitial") {
                    val initial = pending
                    pending = null
                    result.success(initial)
                } else result.notImplemented()
            }
        }
        publish()
    }

    fun onNewIntent(intent: Intent) = receive(intent, notify = true)

    private fun receive(intent: Intent?, notify: Boolean) {
        // Recents can recreate an empty task using its old shortcut base intent.
        if (intent != null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val section = when (intent?.action) {
            "com.reddraggone9.tandemlog.OPEN_TASKS" -> "tasks"
            "com.reddraggone9.tandemlog.OPEN_FOOD" -> "food"
            else -> return
        }
        val request = mapOf("id" to ++sequence, "section" to section)
        pending = request
        if (notify) channel?.invokeMethod("openSection", request, object : MethodChannel.Result {
            override fun success(result: Any?) {
                // Do not erase a newer intent while delivery of this one finishes.
                if (pending === request) pending = null
            }
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {} // Dart startup will take the latest pending request.
        })
    }

    private fun publish() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val manager = activity.getSystemService(ShortcutManager::class.java) ?: return
        try {
            val shortcuts = listOf(
                shortcut("tandemlog_tasks", "Tasks", "com.reddraggone9.tandemlog.OPEN_TASKS", 0, R.mipmap.ic_launcher),
                shortcut("tandemlog_food", "Food", "com.reddraggone9.tandemlog.OPEN_FOOD", 1, R.mipmap.ic_shortcut_food),
            )
            // Stable IDs also refresh copies already pinned by a launcher,
            // including a pinned shortcut no longer in its dynamic list.
            manager.updateShortcuts(shortcuts)
            manager.dynamicShortcuts = shortcuts
        } catch (failure: RuntimeException) {
            Log.w("Tandemlog", "Launcher shortcuts unavailable", failure)
        }
    }

    @android.annotation.TargetApi(25)
    private fun shortcut(id: String, label: String, action: String, rank: Int, icon: Int) =
        ShortcutInfo.Builder(activity, id)
            .setShortLabel(label)
            .setRank(rank)
            .setIcon(Icon.createWithResource(activity, icon))
            .setIntent(Intent(activity, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            })
            .build()

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
