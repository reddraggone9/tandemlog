package dev.tandemlog.tandemlog

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** Folder capabilities, never guessed filesystem paths. Resolve children anew. */
class MainActivity : FlutterActivity() {
    private var picker: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "tandemlog/folders").setMethodCallHandler { call, result ->
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
                        "list" -> children(tree).map { mapOf("name" to it.first) }
                        "read" -> contentResolver.openInputStream(child(tree, name!!) ?: error("Missing $name"))!!.use { stream ->
                            val bytes = stream.readBytes()
                            bytes
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
                    main.post { result.error("folder", "Folder access failed: ${e.message}. Re-select the folder if permission was revoked.", null) }
                }
            }
        }
    }
    private fun children(tree: Uri): List<Pair<String, Uri>> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val result = mutableListOf<Pair<String, Uri>>()
        contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)!!.use { cursor ->
            while (cursor.moveToNext()) result.add(cursor.getString(1) to DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0)))
        }
        return result
    }
    private fun child(tree: Uri, name: String): Uri? = children(tree).firstOrNull { it.first == name }?.second
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
