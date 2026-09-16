import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        load(FileInputStream(localPropertiesFile))
    }
}

val tomtomApiKey = localProperties.getProperty("TOMTOM_API_KEY") ?: "DEMO_TOMTOM_KEY"
val geminiApiKey = localProperties.getProperty("GEMINI_API_KEY") ?: "DEMO_GEMINI_KEY"
val groqApiKey = localProperties.getProperty("GROQ_API_KEY") ?: "DEMO_GROQ_KEY"
// 10.0.2.2 is the Android emulator's alias for the host machine's localhost — reaches `server/`
// running on the dev machine out of the box. A physical device needs the host's LAN IP instead
// (set CENTRAL_REGISTRY_BASE_URL in local.properties, e.g. http://192.168.1.23:3001).
val centralRegistryBaseUrl = localProperties.getProperty("CENTRAL_REGISTRY_BASE_URL") ?: "http://10.0.2.2:3001"

android {
    namespace = "com.urbanpulse.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.urbanpulse.app"
        minSdk = 26
        targetSdk = 34
        versionCode = 4
        versionName = "1.3.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }

        buildConfigField("String", "TOMTOM_API_KEY", "\"$tomtomApiKey\"")
        buildConfigField("String", "GEMINI_API_KEY", "\"$geminiApiKey\"")
        buildConfigField("String", "GROQ_API_KEY", "\"$groqApiKey\"")
        buildConfigField("String", "CENTRAL_REGISTRY_BASE_URL", "\"$centralRegistryBaseUrl\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            buildConfigField("String", "TOMTOM_API_KEY", "\"$tomtomApiKey\"")
            buildConfigField("String", "GEMINI_API_KEY", "\"$geminiApiKey\"")
            buildConfigField("String", "GROQ_API_KEY", "\"$groqApiKey\"")
            buildConfigField("String", "CENTRAL_REGISTRY_BASE_URL", "\"$centralRegistryBaseUrl\"")
        }
        debug {
            buildConfigField("String", "TOMTOM_API_KEY", "\"$tomtomApiKey\"")
            buildConfigField("String", "GEMINI_API_KEY", "\"$geminiApiKey\"")
            buildConfigField("String", "GROQ_API_KEY", "\"$groqApiKey\"")
            buildConfigField("String", "CENTRAL_REGISTRY_BASE_URL", "\"$centralRegistryBaseUrl\"")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        viewBinding = true
        buildConfig = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/DEPENDENCIES"
            excludes += "META-INF/LICENSE"
            excludes += "META-INF/LICENSE.txt"
            excludes += "META-INF/license.txt"
            excludes += "META-INF/NOTICE"
            excludes += "META-INF/NOTICE.txt"
            excludes += "META-INF/notice.txt"
            excludes += "META-INF/ASL2.0"
            excludes += "META-INF/*.kotlin_module"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.7.0")
    // Jetpack Compose was in the original project template but every screen here is a real
    // classic View/XML layout (see the layout files driving each Activity/Fragment) — no
    // Composable is ever rendered, so the Compose BOM + UI/Material3 artifacts were pure dead
    // weight and have been removed.
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.viewpager2:viewpager2:1.0.0")

    // Charting library
    implementation("com.github.PhilJay:MPAndroidChart:v3.1.0")

    // Image loading with Coil
    implementation("io.coil-kt:coil:2.6.0")

    // Health Connect
    implementation("androidx.health.connect:connect-client:1.1.0-alpha07")

    // Retrofit & OkHttp & Gson (Networking & MCP Engine)
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.google.code.gson:gson:2.10.1")

    // TomTom Search SDK (used by LiveMapFragment.kt / MedicalActivity.kt for real POI search).
    // map-display and route-planner-online were declared but never referenced anywhere in the
    // codebase — all real map rendering here goes through a WebView/Leaflet, and all real
    // routing goes through direct TomTom REST calls (see CentralRegistryClient/LiveMapFragment),
    // not this native SDK module. It was the single largest contributor to APK size (its native
    // map-rendering .so libraries are bundled for every ABI) for zero functional benefit, so it's
    // removed rather than kept "just in case".
    implementation("com.tomtom.sdk.search:search-online:1.13.0") {
        exclude(group = "com.google.protobuf", module = "protobuf-java")
        exclude(group = "com.google.protobuf", module = "protobuf-kotlin")
    }

    // Google Generative AI (Gemini)
    implementation("com.google.ai.client.generativeai:generativeai:0.9.0")

    // Firebase (Authentication, Firestore & Storage)
    implementation(platform("com.google.firebase:firebase-bom:32.8.1"))
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-storage-ktx")

    // Play Services Location
    implementation("com.google.android.gms:play-services-location:21.2.0")

    // Androidx Fragment KTX
    implementation("androidx.fragment:fragment-ktx:1.6.2")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
