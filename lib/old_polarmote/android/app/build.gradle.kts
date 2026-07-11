import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun resolvePubspecVersionNameAndCode(): Pair<String, Int> {
    val pubspecFile = rootProject.file("../pubspec.yaml")
    if (!pubspecFile.exists()) return Pair(flutter.versionName, flutter.versionCode)

    val content = pubspecFile.readText()
    val match =
        Regex("""(?m)^\s*version:\s*([^\s]+)\s*$""").find(content)?.groupValues?.get(1)
    val versionRaw = match ?: return Pair(flutter.versionName, flutter.versionCode)

    val parts = versionRaw.split("+", limit = 2)
    val name = parts[0]
    val code = parts.getOrNull(1)?.toIntOrNull() ?: flutter.versionCode
    return Pair(name, code)
}

fun resolveAndroidSdkDir(): File? {
    val localProps = rootProject.file("local.properties")
    if (localProps.exists()) {
        val props = Properties()
        localProps.inputStream().use { props.load(it) }
        val sdkDir = props.getProperty("sdk.dir")?.trim()
        if (!sdkDir.isNullOrEmpty()) return file(sdkDir)
    }
    val env = System.getenv("ANDROID_SDK_ROOT") ?: System.getenv("ANDROID_HOME")
    if (!env.isNullOrEmpty()) return file(env)
    return null
}

fun resolveNdkVersion(): String? {
    val sdkDir = resolveAndroidSdkDir() ?: return null
    val ndkRoot = File(sdkDir, "ndk")
    if (!ndkRoot.exists()) return null

    fun hasSourceProps(version: String): Boolean =
        File(ndkRoot, "$version/source.properties").exists()

    val flutterNdk = flutter.ndkVersion
    if (!flutterNdk.isNullOrBlank() && hasSourceProps(flutterNdk)) {
        return flutterNdk
    }

    val candidates =
        ndkRoot.listFiles()
            ?.filter { it.isDirectory && File(it, "source.properties").exists() }
            ?.map { it.name }
            ?.sorted()
            ?: emptyList()

    return candidates.lastOrNull()
}

fun isWindowsHost(): Boolean {
    val osName = System.getProperty("os.name")?.lowercase() ?: ""
    return osName.contains("windows")
}

fun resolveRustBuildProfile(taskNames: List<String>): String {
    val lowered = taskNames.map { it.lowercase() }
    return if (lowered.any { it.contains("release") || it.contains("profile") }) {
        "release"
    } else {
        "debug"
    }
}

fun resolveRustAndroidAbis(): String {
    val fromProject =
        (findProperty("asmoteRustAbis") as? String)?.trim().orEmpty()
    if (fromProject.isNotEmpty()) return fromProject
    val fromEnv = System.getenv("ASMOTE_ANDROID_ABIS")?.trim().orEmpty()
    if (fromEnv.isNotEmpty()) return fromEnv
    return ""
}

val rustCoreDir = rootProject.file("../native/asmote_native_core")
val rustAndroidJniDir = file("$buildDir/generated/rustJniLibs")
val rustAndroidAbis = resolveRustAndroidAbis()
val rustBuildInputs =
    fileTree(rustCoreDir) {
        include("Cargo.toml")
        include("Cargo.lock")
        include("src/**/*.rs")
        include("scripts/build_android_libs.ps1")
        include("scripts/build_android_libs.sh")
        include("scripts/perl_lib/**")
    }

android {
    namespace = "com.example.asmote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = resolveNdkVersion() ?: flutter.ndkVersion
    val (pubVersionName, pubVersionCode) = resolvePubspecVersionNameAndCode()

    // 禁用对第三方库AndroidManifest.xml中package属性的检查
    lint {
        disable += "ManifestPackageName"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // 启用核心库脱糖
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.asmote"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = pubVersionCode
        versionName = pubVersionName

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(rustAndroidJniDir)
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
            isMinifyEnabled = false
        }
        release {
            // 使用debug签名配置
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = false
            isMinifyEnabled = false  // 暂时禁用混淆来解决 R8 错误
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // 添加 R8 配置来解决 Google Play Core 缺失类问题
            isShrinkResources = false
        }
    }
    
}

val prepareRustAndroidLibs by tasks.registering {
    group = "rust"
    description = "Build asmote_native_core for Android ABIs and copy into jniLibs."
    inputs.files(rustBuildInputs)
    inputs.property("rustProfile", resolveRustBuildProfile(gradle.startParameter.taskNames))
    inputs.property("rustMinApi", flutter.minSdkVersion)
    inputs.property("rustAbis", rustAndroidAbis)
    inputs.property("skipRustAndroid", System.getenv("ASMOTE_SKIP_RUST_ANDROID") ?: "")
    outputs.dir(rustAndroidJniDir)

    doLast {
        if (System.getenv("ASMOTE_SKIP_RUST_ANDROID") == "1") {
            logger.lifecycle("Skipping Rust Android build because ASMOTE_SKIP_RUST_ANDROID=1")
            return@doLast
        }

        if (!rustCoreDir.exists()) {
            throw GradleException("Rust crate directory not found: ${rustCoreDir.absolutePath}")
        }

        val sdkDir =
            resolveAndroidSdkDir()
                ?: throw GradleException(
                    "Android SDK directory not found. Configure sdk.dir in local.properties or ANDROID_SDK_ROOT.",
                )
        val resolvedNdkVersion =
            resolveNdkVersion()
                ?: throw GradleException(
                    "Android NDK version could not be resolved from SDK: ${sdkDir.absolutePath}",
                )
        val ndkDir = File(sdkDir, "ndk/$resolvedNdkVersion")
        if (!ndkDir.exists()) {
            throw GradleException("Android NDK directory not found: ${ndkDir.absolutePath}")
        }

        val profile = resolveRustBuildProfile(gradle.startParameter.taskNames)
        val minApi = flutter.minSdkVersion
        val isWindows = isWindowsHost()
        if (rustAndroidAbis.isNotBlank()) {
            logger.lifecycle("Rust Android ABI filter: $rustAndroidAbis")
        }
        val script =
            if (isWindows) {
                File(rustCoreDir, "scripts/build_android_libs.ps1")
            } else {
                File(rustCoreDir, "scripts/build_android_libs.sh")
            }
        if (!script.exists()) {
            throw GradleException("Rust Android build script not found: ${script.absolutePath}")
        }

        if (isWindows) {
            exec {
                workingDir = rootProject.projectDir
                commandLine(
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    script.absolutePath,
                    "-CrateDir",
                    rustCoreDir.absolutePath,
                    "-OutputDir",
                    rustAndroidJniDir.absolutePath,
                    "-NdkDir",
                    ndkDir.absolutePath,
                    "-Profile",
                    profile,
                    "-ApiLevel",
                    minApi.toString(),
                    "-Abis",
                    rustAndroidAbis,
                )
            }
        } else {
            exec {
                workingDir = rootProject.projectDir
                commandLine(
                    "sh",
                    script.absolutePath,
                    "--crate-dir",
                    rustCoreDir.absolutePath,
                    "--output-dir",
                    rustAndroidJniDir.absolutePath,
                    "--ndk-dir",
                    ndkDir.absolutePath,
                    "--profile",
                    profile,
                    "--api-level",
                    minApi.toString(),
                    "--abis",
                    rustAndroidAbis,
                )
            }
        }
    }
}

tasks.named("preBuild") {
    dependsOn(prepareRustAndroidLibs)
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:1.8.0"))
    implementation("androidx.core:core-ktx:1.9.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.9.0")
    // 核心库脱糖支持
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
