# JNI downcalls resolve these exact class and native method names.
-keep class com.opencapture.openpocketcine.bridge.SwiftCore {
    native <methods>;
}
-keep class com.opencapture.openpocketcine.feed.OpcVulkan {
    native <methods>;
}

# ML Kit instantiates the ComponentRegistrar named in each MlKitComponentDiscoveryService
# meta-data key by reflection. The firebase-components consumer rule keeps the class names only,
# so R8 full mode strips their constructors, ML Kit never initializes and the first face frame
# throws (OPENPOCKETCINE-ANDROID-18). Same rules as OpenZCine; bundleRelease verifies the dex.
-keep class com.google.mlkit.common.internal.MlKitComponentDiscoveryService { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
