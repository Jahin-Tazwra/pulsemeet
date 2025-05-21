// Configure Java toolchain for all projects
allprojects {
    tasks.withType<JavaCompile> {
        javaCompiler.set(javaToolchains.compilerFor {
            languageVersion.set(JavaLanguageVersion.of(11))
        })
    }
    
    tasks.withType<Test> {
        javaLauncher.set(javaToolchains.launcherFor {
            languageVersion.set(JavaLanguageVersion.of(11))
        })
    }
    
    tasks.withType<JavaExec> {
        javaLauncher.set(javaToolchains.launcherFor {
            languageVersion.set(JavaLanguageVersion.of(11))
        })
    }
}
