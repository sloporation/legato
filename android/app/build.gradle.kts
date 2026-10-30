plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.sloporation.legato"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.sloporation.legato"
        minSdk = 26
        targetSdk = 36
        // the release workflow passes the tag's version (-PlegatoVersion=1.2.3)
        versionName = (project.findProperty("legatoVersion") as String?) ?: "0.1.0"
        versionCode = versionName!!.split(".").map { it.toIntOrNull() ?: 0 }.let { (it + listOf(0, 0, 0)).take(3) }
            .let { (major, minor, patch) -> major * 10000 + minor * 100 + patch }.coerceAtLeast(1)
    }

    // The release key, when there is one (the workflow writes it from the ANDROID_KEYSTORE_* secrets). Phones only install an update
    // signed with the same key as what they have, so releases want this one key for good; without it, the debug key stands in.
    val keystore = System.getenv("LEGATO_KEYSTORE")?.let(::file)?.takeIf { it.exists() }
    signingConfigs {
        if (keystore != null) create("release") {
            storeFile = keystore
            storePassword = System.getenv("LEGATO_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("LEGATO_KEY_ALIAS")
            keyPassword = System.getenv("LEGATO_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.3")
    // playing: ExoPlayer, in a MediaSessionService for the notification, lock screen and headphone buttons
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")      // (Android's own org.json is only a stub in unit tests)
}
