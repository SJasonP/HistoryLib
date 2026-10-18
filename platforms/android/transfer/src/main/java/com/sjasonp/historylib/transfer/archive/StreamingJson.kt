package com.sjasonp.historylib.transfer.archive

import java.io.Reader

/**
 * Minimal streaming JSON tokenizer that can skip to a named array and then
 * yield the raw text of each top-level object without materializing the whole
 * document. It is intentionally narrow: strings, braces, brackets, and commas
 * are tracked correctly; nested arrays are treated as balanced spans.
 */
class StreamingJson(
    private val reader: Reader,
    private val maxObjectChars: Int = DEFAULT_MAX_OBJECT_CHARS,
    private val maxDepth: Int = DEFAULT_MAX_DEPTH,
) {
    private var lookahead: Int = -2

    fun skipToArray(key: String): Boolean {
        val target = "\"$key\"".toCharArray()
        var matched = 0
        while (true) {
            val ch = next()
            if (ch == -1) return false
            if (ch == target[matched].code) {
                matched++
                if (matched == target.size) {
                    return skipWhitespaceToColon() && skipTo('[')
                }
            } else {
                matched = 0
                if (ch == target[0].code) matched = 1
            }
        }
    }

    fun nextObjectText(): String? {
        while (true) {
            val ch = nextNonWhitespace() ?: return null
            if (ch == '{'.code) return readBalancedObject()
            if (ch == ']'.code) return null
            // commas or other separators are skipped
        }
    }

    private fun readBalancedObject(): String {
        val sb = StringBuilder("{")
        var depth = 1
        var inString = false
        var escaped = false
        while (true) {
            val ch = next()
            if (ch == -1) throw StreamingJsonException("JSON object is truncated")
            sb.append(ch.toChar())
            if (sb.length > maxObjectChars) {
                throw StreamingJsonException("JSON object exceeds the supported size")
            }
            if (inString) {
                if (escaped) {
                    escaped = false
                } else if (ch == '\\'.code) {
                    escaped = true
                } else if (ch == '"'.code) {
                    inString = false
                }
            } else {
                when (ch) {
                    '"'.code -> inString = true
                    '{'.code -> {
                        depth++
                        if (depth > maxDepth) {
                            throw StreamingJsonException("JSON nesting exceeds the supported depth")
                        }
                    }
                    '}'.code -> {
                        depth--
                        if (depth == 0) return sb.toString()
                    }
                }
            }
        }
    }

    private fun skipWhitespaceToColon(): Boolean {
        while (true) {
            val ch = nextNonWhitespace() ?: return false
            if (ch == ':'.code) return true
        }
    }

    private fun skipTo(target: Char): Boolean {
        while (true) {
            val ch = nextNonWhitespace() ?: return false
            if (ch == target.code) return true
        }
    }

    private fun nextNonWhitespace(): Int? {
        while (true) {
            val ch = next()
            if (ch == -1) return null
            if (!ch.toChar().isWhitespace()) return ch
        }
    }

    private fun next(): Int {
        if (lookahead != -2) {
            val value = lookahead
            lookahead = -2
            return value
        }
        return reader.read()
    }

    companion object {
        const val DEFAULT_MAX_OBJECT_CHARS = 4 * 1024 * 1024
        const val DEFAULT_MAX_DEPTH = 128
    }
}

class StreamingJsonException(message: String) : IllegalArgumentException(message)
