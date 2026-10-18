package com.sjasonp.historylib.transfer

import java.io.InputStream
import java.io.OutputStream

interface TransferScratch {
    suspend fun <T> withTempFile(suffix: String, block: suspend (ScratchFile) -> T): T
}

interface ScratchFile {
    fun newOutputStream(): OutputStream

    fun newInputStream(): InputStream

    fun delete()
}
