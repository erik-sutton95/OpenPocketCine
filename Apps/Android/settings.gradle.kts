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

// The OpenCine platform build (one Gradle build for every shared Android module): a sibling
// checkout of OpenCine pinned in opencine-pins.txt. Named because its directory is also called
// `Android`. Replace with the published Maven coordinates when OpenCine has a remote.
includeBuild("../../../OpenCine/Android") {
    name = "opencine"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:core")).using(project(":core"))
        substitute(module("com.opencapture.opencine:media")).using(project(":media"))
        substitute(module("com.opencapture.opencine:platform")).using(project(":platform"))
        substitute(module("com.opencapture.opencine:decoder")).using(project(":decoder"))
        substitute(module("com.opencapture.opencine:native-runtime")).using(project(":native-runtime"))
        substitute(module("com.opencapture.opencine:dji")).using(project(":dji"))
        substitute(module("com.opencapture.opencine:vulkan")).using(project(":vulkan"))
        substitute(module("com.opencapture.opencine:multicam")).using(project(":multicam"))
        substitute(module("com.opencapture.opencine:monitor-ui")).using(project(":monitor-ui"))
        substitute(module("com.opencapture.opencine:appkit")).using(project(":appkit"))
        substitute(module("com.opencapture.opencine:camera-controls")).using(project(":camera-controls"))
    }
}

include(":app")
