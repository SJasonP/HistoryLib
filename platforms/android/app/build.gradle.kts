plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

val localReleaseStoreFile = providers.gradleProperty("historylib.releaseStoreFile").orNull
val localReleaseStorePassword = providers.gradleProperty("historylib.releaseStorePassword").orNull
val localReleaseKeyAlias = providers.gradleProperty("historylib.releaseKeyAlias").orNull
val localReleaseKeyPassword = providers.gradleProperty("historylib.releaseKeyPassword").orNull

android {
    namespace = "com.sjasonp.historylib"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.sjasonp.historylib"
        minSdk = 36
        targetSdk = 37
        versionCode = 1
        versionName = "1.4"
        ndk {
            abiFilters += "arm64-v8a"
        }

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    packaging {
        resources {
            excludes += setOf(
                "arm64/libsodium.so",
                "armv6/libsodium.so",
                "linux/libsodium.so",
                "linux64/libsodium.so",
                "mac/aarch64/libsodium.dylib",
                "mac/intel/libsodium.dylib",
                "windows/libsodium.dll",
                "windows64/libsodium.dll",
            )
        }
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
            if (localReleaseStoreFile != null && localReleaseStorePassword != null &&
                localReleaseKeyAlias != null && localReleaseKeyPassword != null
            ) {
                signingConfig = signingConfigs.create("localRelease") {
                    storeFile = file(localReleaseStoreFile)
                    storePassword = localReleaseStorePassword
                    keyAlias = localReleaseKeyAlias
                    keyPassword = localReleaseKeyPassword
                }
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
}

ksp {
    arg("room.schemaLocation", file("schemas").absolutePath)
}

dependencies {
    implementation(project(":core"))
    implementation(project(":transfer"))
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material3.adaptive.navigation)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.paging.runtime)
    implementation(libs.androidx.room.ktx)
    implementation(libs.androidx.room.paging)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.material)
    ksp(libs.androidx.room.compiler)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.room.testing)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
