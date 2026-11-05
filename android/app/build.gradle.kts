import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// O FCM só é ligado quando o google-services.json do flavor existir
// (android/app/src/dev/ e android/app/src/prod/).
if (listOf("dev", "prod").any { file("src/$it/google-services.json").exists() }) {
    apply(plugin = "com.google.gms.google-services")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// Chave do Google Maps SDK for Android: GOOGLE_MAPS_API_KEY em env/<flavor>.json (fora do git),
// o mesmo arquivo passado em --dart-define-from-file. Sem chave, o app usa OpenStreetMap.
@Suppress("UNCHECKED_CAST")
fun mapsApiKey(flavor: String): String {
    val f = rootProject.file("../env/$flavor.json")
    if (!f.exists()) return "SEM_CHAVE"
    val json = groovy.json.JsonSlurper().parse(f) as Map<String, Any?>
    return (json["GOOGLE_MAPS_API_KEY"] as String?)?.takeIf { it.isNotBlank() } ?: "SEM_CHAVE"
}

android {
    namespace = "br.com.radarfamiliar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.radarfamiliar"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        resValues = true
    }

    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Radar Familiar Dev")
            manifestPlaceholders["mapsApiKey"] = mapsApiKey("dev")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Radar Familiar")
            manifestPlaceholders["mapsApiKey"] = mapsApiKey("prod")
        }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sem android/key.properties, assina com a chave de debug (só para testes locais).
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
