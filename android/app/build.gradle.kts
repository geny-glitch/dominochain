import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("io.sentry.android.gradle") version "4.9.0"
}

val releaseKeystorePath = System.getenv("KEYSTORE_PATH")
val releaseKeystorePassword = System.getenv("KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("KEY_ALIAS")
val releaseKeyPassword = System.getenv("KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword
).all { !it.isNullOrBlank() }
val otaVersionCode = System.getenv("OTA_VERSION_CODE")?.let { value ->
    value.toIntOrNull() ?: error("OTA_VERSION_CODE must be a positive integer")
} ?: run {
    val versionJsonFile = rootProject.file("../version.json")
    if (versionJsonFile.exists()) {
        Regex("\"versionCode\"\\s*:\\s*(\\d+)").find(versionJsonFile.readText())
            ?.groupValues?.get(1)?.toIntOrNull() ?: 1
    } else {
        1
    }
}
require(otaVersionCode > 0) { "OTA_VERSION_CODE must be a positive integer" }
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(localPropertiesFile.inputStream())
}
val apiBaseUrlProd = localProperties.getProperty("API_BASE_URL_PROD", "https://dominochain.app")
val apiBaseUrlStaging = localProperties.getProperty("API_BASE_URL_STAGING", "https://beta.dominochain.app")
val sentryDsnProd = localProperties.getProperty("SENTRY_DSN_PROD", localProperties.getProperty("SENTRY_DSN", ""))
val sentryDsnStaging = localProperties.getProperty("SENTRY_DSN_STAGING", sentryDsnProd)

android {
    namespace = "app.dominochain.mobile"
    compileSdk = 34

    defaultConfig {
        applicationId = "app.dominochain.mobile"
        minSdk = 26
        targetSdk = 34
        versionCode = otaVersionCode
        versionName = "1.0"
    }

    flavorDimensions += "environment"
    productFlavors {
        create("prod") {
            dimension = "environment"
            buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrlProd\"")
            buildConfigField("String", "NOTIFICATION_TITLE", "\"Domino Chain\"")
            buildConfigField("String", "SENTRY_DSN", "\"$sentryDsnProd\"")
            resValue("string", "app_name", "Domino Chain")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrlStaging\"")
            buildConfigField("String", "NOTIFICATION_TITLE", "\"Domino Chain dev\"")
            buildConfigField("String", "SENTRY_DSN", "\"$sentryDsnStaging\"")
            resValue("string", "app_name", "Domino Chain Staging")
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        buildConfig = true
        viewBinding = true
    }
}

configurations.configureEach {
    exclude(group = "io.sentry", module = "sentry-android-ndk")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.cardview:cardview:1.0.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")

    // Retrofit
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")

    // Coil
    implementation("io.coil-kt:coil:2.5.0")

    // WorkManager
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")

    // Firebase Cloud Messaging
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-messaging-ktx")

    // Sentry - sentry-android-core sans NDK (pas de libs natives = pas de pb 16 KB)
    implementation("io.sentry:sentry-android-core:7.18.0")
}

tasks.register("printVersionCode") {
    doLast {
        println(android.defaultConfig.versionCode)
    }
}
