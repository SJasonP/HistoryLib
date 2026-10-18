// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

val architectureSources = files(
    fileTree("core/src/main") { include("**/*.kt") },
    fileTree("transfer/src/main") { include("**/*.kt") },
    file("core/build.gradle.kts"),
    file("transfer/build.gradle.kts"),
)

val checkArchitecture by tasks.registering {
    group = "verification"
    description = "Checks Android module dependency and source boundaries."
    inputs.files(architectureSources)

    doLast {
        val violations = mutableListOf<String>()
        inputs.files.files.forEach { source ->
            val module = if (source.invariantSeparatorsPath.contains("/core/")) "core" else "transfer"
            if (source.name == "build.gradle.kts") {
                val dependencyText = source.readText()
                if (module == "core" && "project(" in dependencyText) {
                    violations += "${source.invariantSeparatorsPath} must not depend on another project module"
                }
                if (module == "transfer") {
                    Regex("project\\(\"(:[^\"]+)\"\\)").findAll(dependencyText)
                        .map { it.groupValues[1] }
                        .filter { it != ":core" }
                        .forEach { dependency ->
                            violations += "${source.invariantSeparatorsPath} has forbidden dependency $dependency"
                        }
                }
                return@forEach
            }
            val forbiddenPatterns = if (module == "core") {
                listOf(
                    Regex("^import android\\.", RegexOption.MULTILINE),
                    Regex("^import androidx\\.", RegexOption.MULTILINE),
                    Regex("^import com\\.sjasonp\\.historylib\\.transfer", RegexOption.MULTILINE),
                )
            } else {
                listOf(
                    Regex("^import android\\.", RegexOption.MULTILINE),
                    Regex("^import androidx\\.", RegexOption.MULTILINE),
                    Regex("^import com\\.sjasonp\\.historylib\\.(di|feature|ui)", RegexOption.MULTILINE),
                )
            }
            val sourceText = source.readText()
            forbiddenPatterns.forEach { pattern ->
                if (pattern.containsMatchIn(sourceText)) {
                    violations += "${source.invariantSeparatorsPath} matches forbidden $pattern"
                }
            }
        }

        check(violations.isEmpty()) {
            "Architecture boundary violations:\n${violations.joinToString("\n")}"
        }
    }
}

subprojects {
    tasks.matching { it.name == "check" }.configureEach {
        dependsOn(rootProject.tasks.named("checkArchitecture"))
    }
}
