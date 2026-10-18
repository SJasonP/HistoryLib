package com.sjasonp.historylib.transfer

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

class FileTransferScratch(context: Context) : TransferScratch {
    private val directory = File(context.cacheDir, "transfer").apply { mkdirs() }

    override suspend fun <T> withTempFile(suffix: String, block: suspend (ScratchFile) -> T): T {
        val file = File.createTempFile("transfer-", suffix, directory)
        return try {
            block(object : ScratchFile {
                override fun newOutputStream(): OutputStream = FileOutputStream(file)
                override fun newInputStream(): InputStream = FileInputStream(file)
                override fun delete() {
                    file.delete()
                }
            })
        } finally {
            file.delete()
        }
    }
}
