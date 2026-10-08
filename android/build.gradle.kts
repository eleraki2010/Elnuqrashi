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

    // يجب تسجيل afterEvaluate قبل evaluationDependsOn، لأن الأخير يُقيِّم مشاريع
    // الإضافات فوراً، فيفشل تسجيل afterEvaluate على مشروع تم تقييمه بالفعل.
    afterEvaluate {
        // بعض إضافات Android تفرض compileSdk أقل من المطلوب (مثلاً file_picker 8.3.7
        // تفرض 34، بينما تتطلب تبعياتها مثل flutter_plugin_android_lifecycle قيمة 36)،
        // مما يفشل checkAarMetadata. نوحّد compileSdk لكل مشاريع الإضافات إلى 36.
        val androidExt = project.extensions.findByName("android") ?: return@afterEvaluate
        val setCompileSdk = androidExt.javaClass.methods.firstOrNull {
            it.name == "setCompileSdk" && it.parameterTypes.size == 1
        }
        if (setCompileSdk != null) {
            setCompileSdk.invoke(androidExt, 36)
        } else {
            project.logger.warn("تعذّر رفع compileSdk للمشروع ${project.name}")
        }
    }

    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
