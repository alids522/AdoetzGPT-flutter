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

subprojects {
    afterEvaluate {
        if (name == "mp_audio_stream") {
            extensions.findByName("android")?.let { androidExtension ->
                val methods = androidExtension.javaClass.methods
                val setCompileSdk =
                    methods.firstOrNull { it.name == "setCompileSdk" && it.parameterTypes.size == 1 }
                        ?: methods.firstOrNull {
                            it.name == "setCompileSdkVersion" && it.parameterTypes.size == 1
                        }
                setCompileSdk?.invoke(androidExtension, 34)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
