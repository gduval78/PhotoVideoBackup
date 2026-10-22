import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "gduvalsc.photovideobackup"
    compileSdk = 36

    defaultConfig {
        applicationId = "gduvalsc.photovideobackup"
        minSdk = 28                  // >= 28: the platform BouncyCastle is repackaged, so smbj's own copy does not clash
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        // The 8 languages of the iOS app: only these are packaged (libraries bring dozens of others).
        resourceConfigurations += listOf("en", "fr", "de", "es", "it", "pt", "zh-rCN", "ru")
    }

    // Release signing: a local keystore (never in the repository) described by keystore.properties.
    val ksFile = rootProject.file("keystore.properties")
    if (ksFile.exists()) {
        val ks = Properties().apply { ksFile.inputStream().use { load(it) } }
        signingConfigs {
            create("release") {
                storeFile = rootProject.file(ks.getProperty("storeFile"))
                storePassword = ks.getProperty("storePassword")
                keyAlias = ks.getProperty("keyAlias")
                keyPassword = ks.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (ksFile.exists()) signingConfig = signingConfigs.getByName("release")
        }
    }
    // "qa": the minified release code (R8) but debuggable and debug-signed, so the Pro debug toggle works and it
    // installs over a debug build — the way to smoke-test what R8 does to smbj/serialization without a purchase.
    buildTypes.create("qa") {
        initWith(buildTypes.getByName("release"))
        isDebuggable = true
        signingConfig = signingConfigs.getByName("debug")
        matchingFallbacks += "release"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1,DEPENDENCIES,LICENSE*,NOTICE*}"
            excludes += "/META-INF/versions/**"
            excludes += "META-INF/*.kotlin_module"
        }
    }
    lint { abortOnError = false }
}

dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.appcompat:appcompat:1.7.0")      // per-app language (AppCompatDelegate.setApplicationLocales)
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.fragment:fragment:1.8.5")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.android.billingclient:billing-ktx:8.0.0")
    implementation("com.hierynomus:smbj:0.13.0")
    // LUT Grade: Transformer re-encodes a video through a 3D LUT effect; ExoPlayer previews it live.
    implementation("androidx.media3:media3-common:1.4.1")
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-ui:1.4.1")
    implementation("androidx.media3:media3-effect:1.4.1")
    implementation("androidx.media3:media3-transformer:1.4.1")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
