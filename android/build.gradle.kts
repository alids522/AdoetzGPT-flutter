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
    if (name == "mp_audio_stream") {
        val buildFile = file("${projectDir.absolutePath}/build.gradle")
        if (buildFile.exists()) {
            var content = buildFile.readText()
            if (content.contains("compileSdkVersion 31")) {
                content = content.replace("compileSdkVersion 31", "compileSdkVersion 34")
                buildFile.writeText(content)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
