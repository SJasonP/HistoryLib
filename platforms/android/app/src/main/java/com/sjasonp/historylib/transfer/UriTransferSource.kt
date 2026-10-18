package com.sjasonp.historylib.transfer

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import java.io.InputStream

class UriTransferSource(
    private val resolver: ContentResolver,
    private val uri: Uri,
    override val kind: TransferSourceKind,
) : TransferSource {
    override val traversalIdentity: String get() = uri.normalizeScheme().toString()
    override val displayName: String
        get() = queryDisplayName(uri) ?: uri.lastPathSegment.orEmpty()

    override suspend fun children(): List<TransferSource> {
        if (kind != TransferSourceKind.DIRECTORY) return emptyList()
        return listChildren(uri).map { child ->
            val childKind = if (isDirectory(child)) TransferSourceKind.DIRECTORY else TransferSourceKind.FILE
            UriTransferSource(resolver, child, childKind)
        }
    }

    override suspend fun <T> withInputStream(block: suspend (InputStream) -> T): T {
        val stream = resolver.openInputStream(uri) ?: error("Cannot open $displayName")
        return stream.use { block(it) }
    }

    private fun listChildren(treeUri: Uri): List<Uri> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getDocumentId(treeUri),
        )
        val result = mutableListOf<Uri>()
        resolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_MIME_TYPE),
            null,
            null,
            null,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val mimeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(idColumn)
                val mimeType = cursor.getString(mimeColumn)
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                val displayName = queryDisplayName(documentUri) ?: documentUri.lastPathSegment.orEmpty()
                if (displayName.startsWith(".")) continue
                if (mimeType != DocumentsContract.Document.MIME_TYPE_DIR && !isJson(documentUri)) continue
                result += documentUri
            }
        }
        return result
    }

    private fun isDirectory(uri: Uri): Boolean {
        return queryMimeType(uri) == DocumentsContract.Document.MIME_TYPE_DIR
    }

    private fun isJson(uri: Uri): Boolean {
        return (queryDisplayName(uri) ?: uri.lastPathSegment.orEmpty()).endsWith(".json", ignoreCase = true)
    }

    private fun queryDisplayName(uri: Uri): String? {
        return resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    private fun queryMimeType(uri: Uri): String? {
        return resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }
}
