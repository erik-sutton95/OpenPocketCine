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

// Candidate shared contracts (OpenCine plan CORE-02): a sibling checkout of OpenCineCore.
// Named because OpenCineUI's included build also lives in a directory called `Android`.
// Replace with the published Maven coordinate when OpenCineCore has a remote.
includeBuild("../../../OpenCineCore/Android") {
    name = "opencinecore"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:core")).using(project(":core"))
    }
}

include(":app")
include(":core-api")

include(":monitor-ui")
