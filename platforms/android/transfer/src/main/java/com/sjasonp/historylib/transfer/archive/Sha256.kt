package com.sjasonp.historylib.transfer.archive

import java.security.MessageDigest

object Sha256 {
    fun of(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }
}
