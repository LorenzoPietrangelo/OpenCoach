plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.opencoach.coach_mobile"
    // tor-android 0.4.9 chiede di compilare con le API 37; il comportamento
    // dell'app lo decide targetSdk, che resta quello di Flutter.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "org.opencoach.coach_mobile"
        // Android 8.0 (§2).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Come l'app dell'atleta, firmata con la chiave di debug finché non
            // ce n'è una propria (decisione 0002).
            signingConfig = signingConfigs.getByName("debug")
            // Si aggiungono alle regole di R8 che mette Flutter.
            proguardFiles("proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Tor incorporato (§10.1): TorService di tor-android, comandato dal
    // trasporto in Dart attraverso la porta di controllo.
    implementation("info.guardianproject:tor-android:0.4.9.14")
    // Controlli in background (§16.4).
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    // Il tema dell'attività: su Android 8 il dialogo del blocco ne chiede uno AppCompat.
    implementation("androidx.appcompat:appcompat:1.7.1")
}
