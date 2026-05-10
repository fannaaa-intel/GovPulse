    plugins {
        id("com.android.application")
        // START: FlutterFire Configuration
        id("com.google.gms.google-services")
        // END: FlutterFire Configuration
        id("kotlin-android")
        // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
        id("dev.flutter.flutter-gradle-plugin")
    }

    android {
        namespace = "com.example.govpulse"
        compileSdk = flutter.compileSdkVersion
        ndkVersion = "29.0.14206865"
        
        compileOptions {
            isCoreLibraryDesugaringEnabled = true  
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }

        kotlinOptions {
            jvmTarget = JavaVersion.VERSION_17.toString()
        }

        tasks.withType<JavaCompile>().configureEach {
            options.compilerArgs.add("-Xlint:-options") 
        }

        defaultConfig {
    applicationId = "com.example.govpulse"
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
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

    flutter {
        source = "../.."
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    }


