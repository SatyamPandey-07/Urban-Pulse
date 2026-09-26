allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Some plugins (e.g. geocoding_android) hardcode an old compileSdk that their own
// androidx dependencies reject; compile every plugin module against a recent SDK.
// Plugins written for AGP 9 (e.g. package_info_plus 10) skip applying the Kotlin
// plugin and expect built-in Kotlin support. This project keeps
// `android.builtInKotlin=false`, so give every Android library module the Kotlin
// plugin as soon as it becomes an Android library.
subprojects {
    plugins.withId("com.android.library") {
        if (!pluginManager.hasPlugin("org.jetbrains.kotlin.android")) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.compileSdk = 36
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
