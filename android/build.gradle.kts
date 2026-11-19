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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Все плагины собираются под compileSdk 36: библиотека Health Connect требует не ниже 35,
// а часть плагинов объявляет меньше
subprojects {
    val fixSdk: Project.() -> Unit = {
        if (name != "app") {
            val ext = extensions.findByName("android")
            if (ext != null) {
                ext.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType).invoke(ext, 36)
            }
        }
    }
    if (state.executed) fixSdk() else afterEvaluate { fixSdk() }
}
