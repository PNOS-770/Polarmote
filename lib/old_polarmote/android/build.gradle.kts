// Top-level build file where you can add configuration options common to all sub-projects/modules.
import com.android.build.api.dsl.LibraryExtension

plugins {
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("dev.flutter.flutter-gradle-plugin") apply false
}

// Align Gradle outputs with Flutter tool expectations (build/app/...).
buildDir = file("../build")

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            if (namespace == null || namespace!!.isBlank()) {
                namespace = project.group.toString()
            }
        }
    }
    buildDir = file("${rootProject.buildDir}/${project.name}")
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
