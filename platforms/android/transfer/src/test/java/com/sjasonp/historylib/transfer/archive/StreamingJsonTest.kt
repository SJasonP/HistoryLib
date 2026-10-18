package com.sjasonp.historylib.transfer.archive

import java.io.StringReader
import org.junit.Assert.assertThrows
import org.junit.Test

class StreamingJsonTest {
    @Test
    fun rejectsTruncatedObject() {
        val stream = StreamingJson(StringReader("{\"items\":[{\"title\":\"unfinished"))
        stream.skipToArray("items")

        assertThrows(StreamingJsonException::class.java) { stream.nextObjectText() }
    }

    @Test
    fun rejectsOversizedObject() {
        val stream = StreamingJson(StringReader("{\"items\":[{\"value\":\"12345\"}]}"), maxObjectChars = 10)
        stream.skipToArray("items")

        assertThrows(StreamingJsonException::class.java) { stream.nextObjectText() }
    }

    @Test
    fun rejectsExcessiveNesting() {
        val stream = StreamingJson(StringReader("{\"items\":[{{{}}}]}"), maxDepth = 2)
        stream.skipToArray("items")

        assertThrows(StreamingJsonException::class.java) { stream.nextObjectText() }
    }
}
