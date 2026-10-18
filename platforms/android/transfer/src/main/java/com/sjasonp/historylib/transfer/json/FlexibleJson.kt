package com.sjasonp.historylib.transfer.json

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

object FlexibleJson {
    fun longOrNull(value: JsonElement?): Long? {
        return when (value) {
            null -> null
            is JsonPrimitive -> value.longOrNull ?: value.content.toLongOrNull()
            else -> null
        }
    }

    fun intOrNull(value: JsonElement?): Int? {
        return when (value) {
            null -> null
            is JsonPrimitive -> value.intOrNull ?: value.content.toIntOrNull()
            else -> null
        }
    }

    fun stringOrNull(value: JsonElement?): String? {
        return when (value) {
            null -> null
            is JsonPrimitive -> value.content
            else -> value.toString()
        }
    }

    fun booleanOrNull(value: JsonElement?): Boolean? {
        return when (value) {
            null -> null
            is JsonPrimitive -> value.booleanOrNull ?: value.content.toBooleanStrictOrNull()
            else -> null
        }
    }

    fun recordString(obj: JsonObject, key: String): String? = stringOrNull(obj[key])
}
