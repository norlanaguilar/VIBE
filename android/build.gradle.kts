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
    
    // Auto-patch para plugins de Flutter obsoletos (como flutter_inappwebview) que usan proguard-android.txt
    // Esto previene el error "is no longer supported since it includes -dontoptimize" en AGP 8+
    val pluginBuildFile = project.buildFile
    if (pluginBuildFile.exists()) {
        val content = pluginBuildFile.readText()
        if (content.contains("proguard-android.txt\"")) {
            pluginBuildFile.writeText(content.replace("proguard-android.txt\"", "proguard-android-optimize.txt\""))
        } else if (content.contains("proguard-android.txt'")) {
            pluginBuildFile.writeText(content.replace("proguard-android.txt'", "proguard-android-optimize.txt'"))
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

