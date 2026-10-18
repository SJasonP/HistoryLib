package com.sjasonp.historylib.data

import android.content.Context
import android.graphics.BitmapFactory
import com.sjasonp.historylib.core.repository.FaviconRepository
import com.sjasonp.historylib.core.repository.StorageUsage
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.security.MessageDigest
import java.util.Collections
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

class HttpFaviconRepository(context: Context) : FaviconRepository {
    private val appContext = context.applicationContext
    private val cacheDir = File(context.cacheDir, "favicons").apply { mkdirs() }
    private val activeConnections = Collections.synchronizedSet(mutableSetOf<HttpURLConnection>())

    override suspend fun favicon(host: String): ByteArray? = withContext(Dispatchers.IO) {
        val normalized = host.trim().lowercase()
        if (normalized.isBlank()) return@withContext null
        val cacheFile = File(cacheDir, "${hash(normalized)}.bin")
        if (cacheFile.isFile) {
            if (cacheFile.length() > 0) return@withContext cacheFile.readBytes()
            if (System.currentTimeMillis() - cacheFile.lastModified() < NEGATIVE_CACHE_MILLIS) return@withContext null
            cacheFile.delete()
        }

        val bytes = fetch(normalized)
        if (bytes == null || !isDecodableImage(bytes)) {
            cacheFile.writeBytes(byteArrayOf())
            return@withContext null
        }
        cacheFile.writeBytes(bytes)
        bytes
    }

    override suspend fun clear() = withContext(Dispatchers.IO) {
        activeConnections.toList().forEach { it.disconnect() }
        activeConnections.clear()
        cacheDir.listFiles()?.forEach { it.delete() }
        Unit
    }

    override suspend fun cacheUsageBytes(): Long = withContext(Dispatchers.IO) {
        cacheDir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    override suspend fun storageUsage(): StorageUsage = withContext(Dispatchers.IO) {
        val cacheBytes = cacheDir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        val dataRoot = appContext.cacheDir.parentFile ?: appContext.filesDir
        val dataBytes = dataRoot.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        StorageUsage(
            clearableBytes = cacheBytes,
            nonClearableBytes = (dataBytes - cacheBytes).coerceAtLeast(0L),
        )
    }

    private suspend fun fetch(host: String): ByteArray? {
        val candidates = listOf(
            "https://$host/favicon.ico",
            "https://$host/apple-touch-icon.png",
            "https://$host/apple-touch-icon-precomposed.png",
        )
        for (candidate in candidates) {
            coroutineContext.ensureActive()
            var connection: HttpURLConnection? = null
            try {
                var current = URL(candidate)
                repeat(MAX_REDIRECTS + 1) {
                    coroutineContext.ensureActive()
                    if (!isPublicHttpsUrl(current)) return@repeat
                    connection = current.openConnection() as HttpURLConnection
                    activeConnections += connection!!
                    connection!!.connectTimeout = 5_000
                    connection!!.readTimeout = 5_000
                    connection!!.instanceFollowRedirects = false
                    connection!!.requestMethod = "GET"
                    val code = connection!!.responseCode
                    if (code in 200..299) return readBounded(connection!!)
                    if (code !in 300..399) return@repeat
                    val location = connection!!.getHeaderField("Location") ?: return@repeat
                    val next = URL(current, location)
                    connection!!.let {
                        activeConnections -= it
                        it.disconnect()
                    }
                    connection = null
                    current = next
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // try next candidate
            } finally {
                connection?.let {
                    activeConnections -= it
                    it.disconnect()
                }
            }
        }
        return null
    }

    private suspend fun readBounded(connection: HttpURLConnection): ByteArray? {
        val out = ByteArrayOutputStream()
        connection.inputStream.use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var total = 0
            while (true) {
                coroutineContext.ensureActive()
                val read = input.read(buffer)
                if (read == -1) break
                total += read
                if (total > MAX_ICON_BYTES) return null
                out.write(buffer, 0, read)
            }
        }
        return out.toByteArray()
    }

    private fun isPublicHttpsUrl(url: URL): Boolean {
        if (url.protocol.lowercase() != "https" || url.userInfo != null || url.port !in listOf(-1, 443)) return false
        val targetHost = url.host?.trim()?.removeSuffix(".") ?: return false
        if (targetHost.isBlank() || targetHost.equals("localhost", true) || targetHost.endsWith(".local", true)) return false
        return runCatching { InetAddress.getAllByName(targetHost).all(::isPublicAddress) }.getOrDefault(false)
    }

    private fun isPublicAddress(address: InetAddress): Boolean =
        !address.isAnyLocalAddress &&
            !address.isLoopbackAddress &&
            !address.isLinkLocalAddress &&
            !address.isSiteLocalAddress &&
            !address.isMulticastAddress

    private fun isDecodableImage(bytes: ByteArray): Boolean {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return try {
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            options.outWidth > 0 && options.outHeight > 0
        } catch (_: Exception) {
            false
        }
    }

    private fun hash(value: String): String {
        return MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val MAX_ICON_BYTES = 5 * 1024 * 1024
        private const val MAX_REDIRECTS = 5
        private const val NEGATIVE_CACHE_MILLIS = 6 * 60 * 60 * 1000L
    }
}
