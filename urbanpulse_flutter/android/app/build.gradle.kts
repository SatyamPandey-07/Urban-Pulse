plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.urbanpulse.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Same application id as the Kotlin build this replaces.
        applicationId = "com.urbanpulse.app"
        // Matches the original app's minSdk 26 (Android 8.0), and satisfies every
        // plugin used here (geolocator, sqflite, webview_flutter, speech_to_text).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Garmin's Connect IQ Mobile SDK for Android, which the watch bridge in
    // src/main/kotlin/com/urbanpulse/app/watch uses. Published by Garmin to Maven
    // Central, so unlike the iOS half nothing has to be fetched by hand.
    implementation("com.garmin.connectiq:ciq-companion-app-sdk:2.2.0")

    // ActivityCompat / ContextCompat for the SEND_SMS runtime permission.
    implementation("androidx.core:core-ktx:1.15.0")
}
