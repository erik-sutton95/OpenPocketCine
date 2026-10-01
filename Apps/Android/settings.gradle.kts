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
        substitute(module("com.opencapture.opencine:media")).using(project(":media"))
    }
}

// Manufacturer-independent multicam engine (OpenCine plan MULTI-02), the sibling checkout
// ../OpenCineMulticam. Its own build includes OpenCineCore under the same name, so one Core
// build serves both. Replace with the published Maven coordinate when it has a remote.
includeBuild("../../../OpenCineMulticam/Android") {
    name = "opencinemulticam"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:multicam")).using(project(":multicam"))
    }
}

include(":app")
include(":core-api")

// Shared Compose UI from the sibling OpenCineUI checkout (candidate wiring
// until OpenCineUI publishes a release): ~/Work/OpenCineUI next to this repo.
includeBuild("../../../OpenCineUI/Android") {
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:monitor-ui")).using(project(":monitor-ui"))
    }
}
