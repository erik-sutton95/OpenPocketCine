pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "OpenPocketCine"

include(":app")
include(":core-api")

// Shared Compose UI from the sibling OpenCineUI checkout (candidate wiring
// until OpenCineUI publishes a release): ~/Work/OpenCineUI next to this repo.
includeBuild("../../../OpenCineUI/Android") {
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:monitor-ui")).using(project(":monitor-ui"))
    }
}
