package com.touch.tvguide.core

import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.helpers.DefaultHandler
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.Locale
import javax.xml.parsers.SAXParserFactory

/** SAX-based XMLTV parser (SAX exists on both JVM and Android). Tolerant: bad entries are skipped. */
object XmltvParser {
    fun parse(input: InputStream): GuideData {
        val channels = LinkedHashMap<String, Channel>()
        val programs = ArrayList<Program>()
        val parser = SAXParserFactory.newInstance().newSAXParser()
        parser.parse(InputSource(input), object : DefaultHandler() {
            private val text = StringBuilder()
            private var chId: String? = null
            private val names = ArrayList<String>()
            private var logo: String? = null
            private var chCategory: String? = null
            private var pCh: String? = null
            private var pStart = 0L
            private var pStop = 0L
            private var title: String? = null
            private var desc: String? = null
            private var inChannel = false
            private var inProgramme = false

            override fun startElement(u: String?, l: String?, q: String, a: Attributes) {
                text.setLength(0)
                when (q) {
                    "channel" -> { inChannel = true; chId = a.getValue("id"); names.clear(); logo = null }
                    "icon" -> if (inChannel) logo = a.getValue("src")
                    "programme" -> {
                        inProgramme = true; pCh = a.getValue("channel"); title = null; desc = null
                        pStart = parseTime(a.getValue("start")); pStop = parseTime(a.getValue("stop"))
                    }
                }
            }
            override fun characters(ch: CharArray, s: Int, len: Int) { text.append(ch, s, len) }
            override fun endElement(u: String?, l: String?, q: String) {
                val t = text.toString().trim()
                when (q) {
                    "display-name" -> if (inChannel && t.isNotEmpty()) names += t
                    "lcn" -> if (inChannel && t.isNotEmpty()) names.add(0, t)
                    "channel" -> {
                        inChannel = false
                        val id = chId
                        if (id != null) {
                            val num = names.firstOrNull { NUMBER.matches(it) }
                            val name = names.firstOrNull { !NUMBER.matches(it) } ?: id
                            channels[id] = Channel(id, name, num, logo)
                        }
                    }
                    "title" -> if (inProgramme && title == null) title = t
                    "desc" -> if (inProgramme && desc == null) desc = t
                    "programme" -> {
                        inProgramme = false
                        val c = pCh; val ti = title
                        if (c != null && ti != null && pStart > 0 && pStop > pStart)
                            programs += Program(c, ti, desc, pStart, pStop)
                    }
                }
            }
        })
        return GuideData(channels.values.toList(), programs.sortedWith(compareBy({ it.channelId }, { it.startMillis })))
    }

    private val NUMBER = Regex("""\d+(\.\d+)?""")

    /** "20261105180000 +0000" or without offset (treated as UTC). Returns 0 if unparseable. */
    internal fun parseTime(s: String?): Long {
        if (s == null) return 0
        return try {
            val hasZone = s.trim().contains(' ')
            val f = SimpleDateFormat(if (hasZone) "yyyyMMddHHmmss Z" else "yyyyMMddHHmmss", Locale.US)
            if (!hasZone) f.timeZone = java.util.TimeZone.getTimeZone("UTC")
            f.parse(s.trim())!!.time
        } catch (e: Exception) { 0 }
    }
}
