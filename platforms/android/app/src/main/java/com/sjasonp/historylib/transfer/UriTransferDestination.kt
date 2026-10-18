package com.sjasonp.historylib.transfer

import android.content.ContentResolver
import android.net.Uri
import java.io.OutputStream

class UriTransferDestination(
    private val resolver: ContentResolver,
    private val uri: Uri,
) : TransferDestination {
    override suspend fun <T> withOutputStream(
        suggestedFileName: String,
        block: suspend (OutputStream) -> T,
    ): T {
        val stream = resolver.openOutputStream(uri, "w")
            ?: error("Cannot open destination")
        return stream.use { block(it) }
    }
}
