package com.touch.tvguide.data

import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPInputStream

/** Downloads the feed to a file. Throws [IOException] with a user-presentable message on any failure. */
fun interface FeedSource {
    fun download(url: String, into: File)
}

class OkHttpFeedSource(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).callTimeout(5, TimeUnit.MINUTES).build(),
) : FeedSource {
    override fun download(url: String, into: File) {
        if (!FeedConfig.isAcceptableUrl(url)) throw IOException("The feed address must start with https://")
        val req = Request.Builder().url(url).header("User-Agent", FeedConfig.USER_AGENT).build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("The guide server answered ${resp.code}.")
            val body = resp.body ?: throw IOException("The guide server sent an empty answer.")
            if (body.contentLength() > FeedConfig.MAX_DOWNLOAD_BYTES) throw IOException("The guide file is unexpectedly large.")
            var total = 0L
            into.outputStream().use { out ->
                body.byteStream().use { input ->
                    val buf = ByteArray(32 * 1024)
                    while (true) {
                        val n = input.read(buf); if (n < 0) break
                        total += n
                        if (total > FeedConfig.MAX_DOWNLOAD_BYTES) throw IOException("The guide file is unexpectedly large.")
                        out.write(buf, 0, n)
                    }
                }
            }
        }
    }
}

/** Opens a cached feed file, un-gzipping if it starts with the gzip magic bytes. */
fun openFeed(f: File): InputStream {
    val raw = f.inputStream().buffered()
    raw.mark(2)
    val a = raw.read(); val b = raw.read()
    raw.reset()
    return if (a == 0x1f && b == 0x8b) GZIPInputStream(raw) else raw
}
