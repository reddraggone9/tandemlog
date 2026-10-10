package com.reddraggone9.tandemlog

import android.app.Activity
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.database.ContentObserver
import android.database.Cursor
import java.util.TimeZone
import android.net.Uri
import android.provider.DocumentsContract
import android.os.Handler
import android.os.Looper
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.FileOutputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import android.os.ParcelFileDescriptor
import java.util.concurrent.Executors

private class MissingFolderFile(val fileName: String) : java.io.IOException("Missing $fileName")
private class DuplicateCanonicalFile(val fileName: String) : java.io.IOException("Duplicate canonical filename $fileName")

/** Folder capabilities, never guessed filesystem paths. Resolve children anew. */
class MainActivity : FlutterActivity() {
    private var folderEvents: MethodChannel? = null
    private var folderChannel: MethodChannel? = null
    @Volatile private var folderWatch: FolderWatch? = null
    @Volatile private var foldersPaused = false
    private class FolderWatch(val tree: Uri, val token: Long, val sink: EventChannel.EventSink) {
        @Volatile var active = true
        // These resources are accessed only by the single IO executor.
        var cursor: Cursor? = null
        var observer: ContentObserver? = null
    }
    private data class FolderChild(val name: String, val id: String, val uri: Uri, val size: Long?, val modified: Long?) {
        fun observation(): Map<String, Any?> = mapOf("name" to name, "documentId" to id, "size" to size, "modifiedMillis" to modified)
    }
    override fun onPause() {
        foldersPaused = true
        folderWatch?.let { watch -> io.execute { releaseFolderCursor(watch) } }
        super.onPause()
    }
    override fun onResume() {
        super.onResume()
        foldersPaused = false
        folderWatch?.let { watch -> io.execute { refreshFolderWatch(watch) } }
    }
    private var timeChannel: MethodChannel? = null
    private var observingTime = false
    private val timeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            TimeZone.setDefault(null) // reread OS zone, including equal-offset changes
            timeChannel?.invokeMethod("changed", null)
        }
    }
    private fun stopTimeObservation() {
        if (observingTime) { unregisterReceiver(timeReceiver); observingTime = false }
    }
    override fun cleanUpFlutterEngine(engine: FlutterEngine) {
        stopFolderWatch()
        folderEvents?.setMethodCallHandler(null)
        folderEvents = null
        folderChannel?.setMethodCallHandler(null)
        folderChannel = null
        super.cleanUpFlutterEngine(engine)
    }
    override fun onDestroy() {
        stopFolderWatch()
        folderEvents?.setMethodCallHandler(null)
        folderEvents = null
        folderChannel?.setMethodCallHandler(null)
        folderChannel = null
        stopTimeObservation()
        timeChannel?.setMethodCallHandler(null)
        timeChannel = null
        io.shutdown() // Drain queued cursor/observer cleanup; never retain a service.
        super.onDestroy()
    }
    private var picker: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        timeChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "tandemlog/time").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "zone" -> {
                        TimeZone.setDefault(null)
                        val zone = TimeZone.getDefault()
                        result.success(mapOf("id" to zone.id, "offsetSeconds" to zone.getOffset(System.currentTimeMillis()) / 1000))
                    }
                    "start" -> {
                        if (!observingTime) {
                            val filter = IntentFilter().apply { addAction(Intent.ACTION_TIME_CHANGED); addAction(Intent.ACTION_TIMEZONE_CHANGED) }
                            // Only protected system broadcasts; no exported app receiver or service.
                            registerReceiver(timeReceiver, filter)
                            observingTime = true
                        }
                        result.success(null)
                    }
                    "stop" -> { stopTimeObservation(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }
        // EventChannel wire protocol with token-aware cancellation. Stock
        // EventChannel tears down its current sink before calling onCancel,
        // even when that cancellation belongs to an older subscription.
        val messenger = engine.dartExecutor.binaryMessenger
        folderEvents = MethodChannel(messenger, "tandemlog/folder-events").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                "listen" -> {
                    val sink = object : EventChannel.EventSink {
                        override fun success(event: Any?) { messenger.send("tandemlog/folder-events", StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(event)) }
                        override fun error(code: String, message: String?, details: Any?) { messenger.send("tandemlog/folder-events", StandardMethodCodec.INSTANCE.encodeErrorEnvelope(code, message, details)) }
                        override fun endOfStream() { messenger.send("tandemlog/folder-events", null) }
                    }
                    stopFolderWatch()
                    try {
                        val args = call.arguments as? Map<*, *> ?: error("Missing watch arguments")
                        val tree = Uri.parse(args["tree"] as? String ?: error("Missing tree"))
                        val token = (args["token"] as? Number)?.toLong() ?: error("Missing watch token")
                        val watch = FolderWatch(tree, token, sink)
                        folderWatch = watch
                        io.execute { refreshFolderWatch(watch) }
                    } catch (e: Exception) {
                        sink.error("watch_unavailable", "Folder notifications unavailable; polling remains active.", null)
                    }
                    result.success(null)
                }
                "cancel" -> {
                    val token = ((call.arguments as? Map<*, *>)?.get("token") as? Number)?.toLong()
                    // A delayed cancellation from an old Dart subscription must
                    // not tear down the newly selected folder's observer.
                    if (token == folderWatch?.token) stopFolderWatch()
                    result.success(null)
                }
                else -> result.notImplemented()
                }
            }
        }
        folderChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "tandemlog/folders").also { channel -> channel.setMethodCallHandler { call, result ->
            if (call.method == "pick") {
                if (picker != null) { result.error("busy", "Folder picker is already open", null); return@setMethodCallHandler }
                picker = result
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }, 42)
                return@setMethodCallHandler
            }
            io.execute {
                try {
                    val tree = Uri.parse(call.argument<String>("tree") ?: error("Missing tree"))
                    val name = call.argument<String>("name")
                    if (name != null && !Regex("^[a-zA-Z0-9._-]+$").matches(name)) error("Unsafe filename")
                    val value: Any? = when (call.method) {
                        "list" -> children(tree).map { it.observation() }
                        "read" -> contentResolver.openInputStream(child(tree, name!!) ?: throw MissingFolderFile(name))!!.use { stream ->
                            val limit = call.argument<Number>("maximumBytes")?.toLong()
                            if (limit == null) stream.readBytes() else {
                                require(limit in 0..(32L * 1024 * 1024)) { "Invalid read limit" }
                                val output = ByteArrayOutputStream()
                                val chunk = ByteArray(64 * 1024)
                                while (true) {
                                    val count = stream.read(chunk)
                                    if (count < 0) break
                                    require(output.size().toLong() + count <= limit) { "Input exceeds safe read limits" }
                                    output.write(chunk, 0, count)
                                }
                                output.toByteArray()
                            }
                        }
                        "readFrom" -> {
                            val offset = (call.argument<Number>("offset") ?: error("Missing offset")).toLong()
                            require(offset >= 0) { "Invalid offset" }
                            // Resolve the selected pathname anew; a retained
                            // watcher cursor/old file handle is not its content.
                            val uri = child(tree, name!!) ?: throw MissingFolderFile(name)
                            val descriptor = contentResolver.openFileDescriptor(uri, "r") ?: error("Provider returned no read descriptor")
                            val size = descriptor.statSize
                            if (size < 0) {
                                descriptor.close()
                                null // Pipes/unknown seekability: explicit store fallback.
                            } else if (size < offset) {
                                descriptor.close()
                                error("Log was truncated before the requested offset")
                            } else {
                                ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                                    try {
                                        input.channel.position(offset)
                                    } catch (e: IOException) {
                                        return@use null // Never read/skip the prefix silently.
                                    }
                                    input.readBytes()
                                }
                            }
                        }
                        "append", "create" -> {
                            val existing = child(tree, name!!)
                            if (call.method == "create" && existing != null) error("File already exists")
                            val uri = existing ?: DocumentsContract.createDocument(contentResolver,
                                DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree)),
                                "application/octet-stream", name) ?: error("Provider cannot create file")
                            val bytes = call.argument<ByteArray>("bytes") ?: error("Missing bytes")
                            contentResolver.openFileDescriptor(uri, if (call.method == "append") "wa" else "w")!!.use { fd ->
                                FileOutputStream(fd.fileDescriptor).use { output ->
                                    output.write(bytes)
                                    output.flush()
                                    output.fd.sync()
                                }
                            }
                            null
                        }
                        else -> error("Unknown folder operation")
                    }
                    main.post { result.success(value) }
                } catch (e: Exception) {
                    val code = when (e) {
                        is MissingFolderFile -> "missing_file"
                        is DuplicateCanonicalFile -> "duplicate_file"
                        is SecurityException -> "permission"
                        else -> "folder"
                    }
                    val details = when (e) {
                        is MissingFolderFile -> mapOf("name" to e.fileName)
                        is DuplicateCanonicalFile -> mapOf("name" to e.fileName)
                        else -> null
                    }
                    main.post { result.error(code, "Folder access failed: ${e.message}", details) }
                }
            }
        } }
    }
    private fun queryChildren(tree: Uri): Cursor {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val identity = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        val projection = identity + arrayOf(DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        return try {
            contentResolver.query(uri, projection, null, null, null) ?: error("Provider returned no folder cursor")
        } catch (e: IllegalArgumentException) {
            // Older/custom providers may reject optional columns. Identity and
            // names remain required; unknown metadata never becomes a stamp.
            contentResolver.query(uri, identity, null, null, null) ?: error("Provider returned no folder cursor")
        } catch (e: UnsupportedOperationException) {
            contentResolver.query(uri, identity, null, null, null) ?: error("Provider returned no folder cursor")
        }
    }
    private fun cursorChildren(tree: Uri, cursor: Cursor): List<FolderChild> {
        val result = mutableListOf<FolderChild>()
        val canonicalNames = mutableSetOf<String>()
        val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        fun optionalLong(column: String): Long? {
            val index = cursor.getColumnIndex(column)
            return if (index < 0 || cursor.isNull(index) || cursor.getType(index) != Cursor.FIELD_TYPE_INTEGER) null
                else cursor.getLong(index).takeIf { it >= 0 }
        }
        while (cursor.moveToNext()) {
            val id = cursor.getString(idIndex) ?: error("Missing document identity")
            val name = cursor.getString(nameIndex) ?: error("Missing document name")
            // A provider can expose multiple documents with the same display
            // name. Validate the whole query before child() chooses a URI or
            // any caller opens a read/write descriptor for canonical data.
            if ((name == "tandemlog-space.json" || name.endsWith(".jsonl")) && !canonicalNames.add(name)) {
                throw DuplicateCanonicalFile(name)
            }
            result.add(FolderChild(name, id, DocumentsContract.buildDocumentUriUsingTree(tree, id),
                optionalLong(DocumentsContract.Document.COLUMN_SIZE), optionalLong(DocumentsContract.Document.COLUMN_LAST_MODIFIED)))
        }
        return result
    }
    private fun children(tree: Uri): List<FolderChild> = queryChildren(tree).use { cursor -> cursorChildren(tree, cursor) }
    private fun child(tree: Uri, name: String): Uri? {
        val matches = children(tree).filter { it.name == name }
        if (matches.size > 1) throw DuplicateCanonicalFile(name)
        return matches.firstOrNull()?.uri
    }

    private fun stopFolderWatch() {
        val watch = folderWatch ?: return
        folderWatch = null
        watch.active = false
        io.execute { releaseFolderCursor(watch) }
    }
    private fun releaseFolderCursor(watch: FolderWatch) {
        val observer = watch.observer
        watch.observer = null
        val cursor = watch.cursor
        watch.cursor = null
        if (observer != null) runCatching { contentResolver.unregisterContentObserver(observer) }
        runCatching { cursor?.close() }
    }
    private fun refreshFolderWatch(watch: FolderWatch) {
        if (!watch.active || folderWatch !== watch || foldersPaused) return
        var next: Cursor? = null
        var observer: ContentObserver? = null
        try {
            next = queryChildren(watch.tree)
            val snapshot = cursorChildren(watch.tree, next).map { it.observation() }
            val notifications = if (Build.VERSION.SDK_INT >= 29) next.notificationUris.orEmpty() else listOfNotNull(next.notificationUri)
            if (notifications.isEmpty()) error("Provider has no folder notification URI")
            observer = object : ContentObserver(main) {
                override fun onChange(selfChange: Boolean) {
                    if (watch.active && folderWatch === watch && !foldersPaused) io.execute { refreshFolderWatch(watch) }
                }
            }
            notifications.distinct().forEach { contentResolver.registerContentObserver(it, true, observer) }
            if (!watch.active || folderWatch !== watch || foldersPaused) return
            // Open/register the replacement before closing the old cursor: AOSP
            // FileSystemProvider's directory observer lives with its cursors.
            releaseFolderCursor(watch)
            watch.cursor = next
            watch.observer = observer
            next = null
            observer = null
            main.post {
                if (watch.active && folderWatch === watch && !foldersPaused) watch.sink.success(mapOf(
                    "tree" to watch.tree.toString(), "token" to watch.token, "files" to snapshot))
            }
        } catch (e: Exception) {
            releaseFolderCursor(watch)
            main.post {
                if (watch.active && folderWatch === watch && !foldersPaused) watch.sink.error(
                    "watch_unavailable", "Folder notifications unavailable; polling remains active.", null)
            }
        } finally {
            try {
                if (observer != null) contentResolver.unregisterContentObserver(observer)
            } finally {
                next?.close()
            }
        }
    }
    @Deprecated("Legacy activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 42) return
        val result = picker ?: return
        picker = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result.success(null); return }
        try {
            val uri = data.data!!
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, flags)
            result.success(uri.toString())
        } catch (e: Exception) { result.error("permission", "Cannot retain folder access: ${e.message}", null) }
    }
}
