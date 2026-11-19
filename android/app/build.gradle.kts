import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle Plugin подключается после плагинов Android и Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

// Ключ подписи release-сборки (docs/RELEASE.md). Берётся из android/key.properties (локально)
// или из переменных окружения (CI, секреты репозитория). В репозиторий ключ и пароли не попадают.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    keyProps.getProperty(prop)?.takeIf { it.isNotBlank() } ?: System.getenv(env)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "LIFEOS_KEYSTORE_PATH")
val hasReleaseKey = releaseStoreFile != null && file(releaseStoreFile).exists()

android {
    // Постоянный идентификатор: его смена = другое приложение (обновление не встанет поверх)
    namespace = "io.github.yrgez.lifeos"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.yrgez.lifeos"
        // 26 (Android 8.0) — минимум для Health Connect
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Версия — из pubspec.yaml; номер сборки CI задаёт числом коммитов (--build-number), он только растёт
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingValue("storePassword", "LIFEOS_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "LIFEOS_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "LIFEOS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Без ключа — отладочная подпись: сборка для проверки, но обновить ею установленную версию нельзя
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

if (!hasReleaseKey) {
    logger.warn("LIFE OS: ключ подписи не найден — release-сборка подписана отладочным ключом (docs/RELEASE.md)")
}

dependencies {
    // Theme.AppCompat для системного окна биометрии
    implementation("androidx.appcompat:appcompat:1.7.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
