package com.sktechstudio.status_saver

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Handles Android folder selection and file operations requested by Flutter.
 */
class MainActivity: FlutterActivity() {
    /** Must match the method-channel name used by the Flutter application. */
    private val CHANNEL = "com.sktechstudio.status_saver/saf"

    /** Holds the folder-picker result until Android returns the user's choice. */
    private var pendingResult: MethodChannel.Result? = null

    /** Registers the native methods that Flutter can invoke through the channel. */
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDirectory" -> {
                    // Keep the result until the folder picker returns a selection.
                    pendingResult = result
                    val initialPath = call.argument<String>("initialPath")
                    requestFolderAccess(initialPath)
                }
                "getFilesFromUri" -> {
                    // Read and cache the folder contents off the UI thread.
                    val uriStr = call.argument<String>("uri")
                    if (uriStr != null) {
                        Thread {
                            val files = fetchFilesAndCache(Uri.parse(uriStr))
                            runOnUiThread { result.success(files) }
                        }.start()
                    } else {
                        result.error("INVALID_URI", "URI is null", null)
                    }
                }
                "saveFile" -> {
                    // Copy the requested media file off the UI thread.
                    val sourceUriStr = call.argument<String>("sourceUri")
                    val targetPath = call.argument<String>("targetPath")
                    if (sourceUriStr != null && targetPath != null) {
                        Thread {
                            val success = saveMediaFile(Uri.parse(sourceUriStr), targetPath)
                            runOnUiThread { result.success(success) }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "Missing arguments", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Opens Android's system folder picker, optionally starting at [initialPath].
     *
     * The requested flags allow the app to retain read and write access to the
     * directory after the picker closes.
     */
    private fun requestFolderAccess(initialPath: String?) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && initialPath != null) {
            val uri = Uri.parse("content://com.android.externalstorage.documents/document/primary%3A$initialPath")
            intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
        }
        startActivityForResult(intent, 1001)
    }

    /** Returns the selected folder URI to Flutter when the picker completes. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val uri = data.data
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    pendingResult?.success(uri.toString())
                } else {
                    pendingResult?.success(null)
                }
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }

    /**
     * Lists supported media in [treeUri], copies uncached files into app cache,
     * and returns each file's name and cached path to Flutter.
     */
    private fun fetchFilesAndCache(treeUri: Uri): ArrayList<HashMap<String, String>> {
        val fileList = ArrayList<HashMap<String, String>>()
        val dir = DocumentFile.fromTreeUri(context, treeUri)
        
        dir?.listFiles()?.forEach { file ->
            val name = file.name
            if (name != null && (name.endsWith(".jpg") || name.endsWith(".mp4") || name.endsWith(".mkv") || name.endsWith(".png"))) {
                
                val cachedFile = File(context.cacheDir, name)
                if (!cachedFile.exists()) {
                    try {
                        contentResolver.openInputStream(file.uri)?.use { input ->
                            FileOutputStream(cachedFile).use { output ->
                                input.copyTo(output)
                            }
                        }
                    } catch (e: Exception) {
                        return@forEach
                    }
                }
                
                val map = HashMap<String, String>()
                map["name"] = name
                map["uri"] = cachedFile.absolutePath
                fileList.add(map)
            }
        }
        return fileList
    }

    /**
     * Copies the file at [sourceUri] to [targetPath].
     *
     * Returns false if the source cannot be opened or the copy fails.
     */
    private fun saveMediaFile(sourceUri: Uri, targetPath: String): Boolean {
        return try {
            val targetFile = File(targetPath)
            targetFile.parentFile?.mkdirs()
            
            val inputStream = if (sourceUri.scheme == "content") {
                contentResolver.openInputStream(sourceUri)
            } else {
                File(sourceUri.path!!).inputStream()
            }
            
            inputStream?.use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}