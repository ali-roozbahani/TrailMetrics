package dev.roozbahani.trailmetrics.data.local.database

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

// Keeps the harness's frozen fixtures equal to Room's exported schema files, so a fixture cannot
// drift from what Room wrote at its version. Host only: the iOS test binary has no access to the
// source tree. The working directory of the host tests is the data module.
class FrozenDatabaseVersionsSchemaTest {

    private val schemaDirectory =
        File("schemas/dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase")

    private fun schemaOf(version: Int): JsonObject =
        Json.parseToJsonElement(File(schemaDirectory, "$version.json").readText())
            .jsonObject.getValue("database").jsonObject

    @Test
    fun `the newest schema file is the current database version`() {
        val versions = schemaDirectory.listFiles().orEmpty().map { it.name.removeSuffix(".json").toInt() }
        assertEquals(CURRENT_DATABASE_VERSION, versions.max())
    }

    @Test
    fun `every frozen fixture matches its version's schema file`() {
        frozenDatabaseVersions.forEach { fixture ->
            val schema = schemaOf(fixture.version)
            val createStatements = schema.getValue("entities").jsonArray.map { entity ->
                val tableName = entity.jsonObject.getValue("tableName").jsonPrimitive.content
                entity.jsonObject.getValue("createSql").jsonPrimitive.content
                    .replace("\${TABLE_NAME}", tableName)
            }
            val setupQueries = schema.getValue("setupQueries").jsonArray.map { it.jsonPrimitive.content }

            assertEquals(fixture.version, schema.getValue("version").jsonPrimitive.int)
            assertEquals(schema.getValue("identityHash").jsonPrimitive.content, fixture.identityHash)
            assertEquals(createStatements + setupQueries, fixture.schemaStatements)
        }
    }
}
