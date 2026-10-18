package com.sjasonp.historylib.transfer

import java.io.InputStream
import java.io.OutputStream

/** Android Uri and ContentResolver details must stay in :app adapters. */
interface TransferSource {
    val displayName: String
    val kind: TransferSourceKind
    val traversalIdentity: String get() = "$kind:$displayName"

    suspend fun children(): List<TransferSource> = emptyList()

    suspend fun <T> withInputStream(block: suspend (InputStream) -> T): T
}

enum class TransferSourceKind {
    FILE,
    DIRECTORY,
}

/** A destination may map to a user-selected file or document-tree directory. */
interface TransferDestination {
    suspend fun <T> withOutputStream(
        suggestedFileName: String,
        block: suspend (OutputStream) -> T,
    ): T
}
