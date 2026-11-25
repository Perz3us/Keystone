// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import java.util.Properties
import java.io.FileInputStream
import com.android.build.gradle.internal.api.ApkVariantOutputImpl

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.perz3us.keystone"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "com.perz3us.keystone"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resourceConfigurations += listOf("en", "ru", "es", "b+pt+BR", "pt-rBR", "pt", "de", "id", "fr", "zh", "it", "ja", "uk")
    }

    signingConfigs {
        val storeFilePath = (keystoreProperties["storeFile"] as? String) ?: System.getenv("KEYSTORE_PATH")
        val storePass = (keystoreProperties["storePassword"] as? String) ?: System.getenv("KEYSTORE_PASSWORD")
        val alias = (keystoreProperties["keyAlias"] as? String) ?: System.getenv("KEY_ALIAS")
        val keyPass = (keystoreProperties["keyPassword"] as? String) ?: System.getenv("KEY_PASSWORD")

        if (!storeFilePath.isNullOrEmpty() && !storePass.isNullOrEmpty() && !alias.isNullOrEmpty() && !keyPass.isNullOrEmpty()) {
            create("release") {
                storeFile = file(storeFilePath)
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass
            }
        }
    }


    flavorDimensions += "version"
    productFlavors {
        create("community") {
            dimension = "version"
            applicationId = "com.perz3us.keystone"
        }
    }

    buildTypes {
        getByName("release") {
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning != null) {
                signingConfig = releaseSigning
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
        }
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs (for IzzyOnDroid/F-Droid)
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles (for Google Play)
        includeInBundle = false
    }

    bundle {
        language {
            enableSplit = false
        }
        density {
            enableSplit = true
        }
        abi {
            enableSplit = true
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

dependencies {
    implementation("androidx.core:core:1.13.1")
}

flutter {
    source = "../.."
}

// One version code for every APK, so people can switch between the universal and the smaller ones.
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode
    }
}

// flutter run looks for app-debug.apk, but the flavor build names it app-community-debug.apk
tasks.register("copyDebugApkForFlutter") {
    doLast {
        val flutterApkDir = file("${project.layout.buildDirectory.get()}/outputs/flutter-apk")
        val communityApk = File(flutterApkDir, "app-community-debug.apk")
        val apkOutDir = file("${project.layout.buildDirectory.get()}/outputs/apk/community/debug/app-community-debug.apk")
        val sourceApk = if (communityApk.exists()) communityApk else if (apkOutDir.exists()) apkOutDir else null
        if (sourceApk != null && sourceApk.exists()) {
            val targetApk = File(flutterApkDir, "app-debug.apk")
            flutterApkDir.mkdirs()
            sourceApk.copyTo(targetApk, overwrite = true)
        }
    }
}

afterEvaluate {
    tasks.findByName("assembleDebug")?.finalizedBy("copyDebugApkForFlutter")
}

