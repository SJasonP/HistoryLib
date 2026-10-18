plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.sjasonp.historylib.transfer"
    compileSdk = 37

    defaultConfig {
        minSdk = 36
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

}

tasks.withType<Test>().configureEach {
    systemProperty(
        "historylib.sharedFixtures",
        rootProject.file("../../shared/fixtures").absolutePath,
    )
}

dependencies {
    api(project(":core"))
    implementation(libs.lazysodium.android)
    implementation(libs.jna)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.lazysodium.java)
    testImplementation(libs.junit)
}
