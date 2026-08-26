// JNI facade over OpenPocketViewCore for the Android app.
//
// Hand-written `@_cdecl` shims matching the `external fun` declarations in
// Apps/Android/app/.../bridge/SwiftCore.kt. Coarse boundary: strings, byte
// arrays, and primitives only.
//
// This file compiles empty on Darwin so `swift test` is unaffected.
#if os(Android)

    import CJNI
    import Foundation
    import OpenPocketViewCore

    // MARK: - JNI plumbing

    private func table(_ env: UnsafeMutablePointer<JNIEnv?>) -> JNINativeInterface {
        env.pointee!.pointee
    }

    private func javaString(
        _ env: UnsafeMutablePointer<JNIEnv?>, _ value: String
    ) -> jstring? {
        value.withCString { table(env).NewStringUTF!(env, $0) }
    }

    private func swiftString(
        _ env: UnsafeMutablePointer<JNIEnv?>, _ value: jstring?
    ) -> String? {
        guard let value,
            let chars = table(env).GetStringUTFChars!(env, value, nil)
        else { return nil }
        defer { table(env).ReleaseStringUTFChars!(env, value, chars) }
        return String(cString: chars)
    }

    private func swiftBytes(
        _ env: UnsafeMutablePointer<JNIEnv?>, _ value: jbyteArray?
    ) -> [UInt8]? {
        guard let value else { return nil }
        let fns = table(env)
        let length = Int(fns.GetArrayLength!(env, value))
        guard length >= 0 else { return nil }
        guard length > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: length)
        out.withUnsafeMutableBytes { raw in
            fns.GetByteArrayRegion!(
                env, value, 0, jsize(length),
                raw.baseAddress?.assumingMemoryBound(to: jbyte.self))
        }
        return out
    }

    private func javaByteArray(
        _ env: UnsafeMutablePointer<JNIEnv?>, _ bytes: [UInt8]
    ) -> jbyteArray? {
        let fns = table(env)
        guard let array = fns.NewByteArray!(env, jsize(bytes.count)) else { return nil }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            fns.SetByteArrayRegion!(
                env, array, 0, jsize(bytes.count), base.assumingMemoryBound(to: jbyte.self))
        }
        return array
    }

    private final class DepacketizerStore: @unchecked Sendable {
        let lock = NSLock()
        var boxes: [Int64: HevcDepacketizerBox] = [:]
        var next: Int64 = 1
    }

    private let depacketizerStore = DepacketizerStore()

    // MARK: - Info

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_coreVersion")
    public func swiftCoreVersion(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?
    ) -> jstring? {
        javaString(env, AndroidSessionWire.coreVersion)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_encodeDuml")
    public func swiftCoreEncodeDuml(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        sender: jint, receiver: jint, seq: jint, flags: jint,
        cmdSet: jint, cmdId: jint, payload: jbyteArray?
    ) -> jbyteArray? {
        let frame = Duml.Frame(
            sender: UInt8(truncatingIfNeeded: sender),
            receiver: UInt8(truncatingIfNeeded: receiver),
            seq: UInt16(truncatingIfNeeded: seq),
            flags: UInt8(truncatingIfNeeded: flags),
            cmdSet: UInt8(truncatingIfNeeded: cmdSet),
            cmdId: UInt8(truncatingIfNeeded: cmdId),
            payload: swiftBytes(env, payload) ?? []
        )
        return javaByteArray(env, Duml.encode(frame))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_scanDuml")
    public func swiftCoreScanDuml(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, data: jbyteArray?
    ) -> jbyteArray? {
        guard let bytes = swiftBytes(env, data) else { return javaByteArray(env, [0, 0]) }
        return javaByteArray(env, AndroidSessionWire.packFrames(DumlTransport.scanFrames(bytes)))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_unpackStatusString")
    public func swiftCoreUnpackStatusString(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, payload: jbyteArray?
    ) -> jstring? {
        javaString(env, Duml.unpackStatusString(swiftBytes(env, payload) ?? []))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_encodeCommand")
    public func swiftCoreEncodeCommand(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        kind: jint, seq: jint, extra: jstring?
    ) -> jbyteArray? {
        guard let commandKind = AndroidSessionWire.CommandKind(rawValue: kind) else { return nil }
        guard
            let frame = AndroidSessionWire.encodeCommand(
                kind: commandKind,
                seq: UInt16(truncatingIfNeeded: seq),
                extra: swiftString(env, extra)
            )
        else { return nil }
        return javaByteArray(env, Duml.encode(frame))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_bleAdvertModelId")
    public func swiftCoreBleAdvertModelId(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, payload: jbyteArray?
    ) -> jint {
        guard let bytes = swiftBytes(env, payload), let id = BleAdvert.modelId(bytes) else {
            return -1
        }
        return jint(id)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_resolveCameraModel")
    public func swiftCoreResolveCameraModel(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        modelId: jint, name: jstring?
    ) -> jstring? {
        let id: Int? = modelId < 0 ? nil : Int(modelId)
        return javaString(
            env, AndroidSessionWire.cameraModelJSON(modelId: id, name: swiftString(env, name)))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_transportHeader")
    public func swiftCoreTransportHeader(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        pktType: jint, payloadLen: jint, sessionId: jint, seq: jint
    ) -> jbyteArray? {
        javaByteArray(
            env,
            DumlTransport.transportHeader(
                pktType: UInt8(truncatingIfNeeded: pktType),
                payloadLen: Int(payloadLen),
                sessionId: UInt16(truncatingIfNeeded: sessionId),
                seq: UInt16(truncatingIfNeeded: seq)
            )
        )
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_routingHeader")
    public func swiftCoreRoutingHeader(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        seq: jint, cmdCounter: jint, drone: jboolean
    ) -> jbyteArray? {
        javaByteArray(
            env,
            DumlTransport.routingHeader(
                seq: UInt16(truncatingIfNeeded: seq),
                cmdCounter: UInt8(truncatingIfNeeded: cmdCounter),
                drone: drone != 0
            )
        )
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_handshakePayload")
    public func swiftCoreHandshakePayload(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, baseSeq: jint
    ) -> jbyteArray? {
        javaByteArray(
            env, DumlTransport.handshakePayload(baseSeq: UInt16(truncatingIfNeeded: baseSeq)))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_ackPayload")
    public func swiftCoreAckPayload(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        peerCursor: jint, ackedDataCursor: jint, extraCursor: jint
    ) -> jbyteArray? {
        javaByteArray(
            env,
            DumlTransport.ackPayload(
                peerCursor: UInt16(truncatingIfNeeded: peerCursor),
                ackedDataCursor: UInt16(truncatingIfNeeded: ackedDataCursor),
                extraCursor: UInt16(truncatingIfNeeded: extraCursor)
            )
        )
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_transportSeq")
    public func swiftCoreTransportSeq(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, datagram: jbyteArray?
    ) -> jint {
        guard let bytes = swiftBytes(env, datagram),
            let seq = DumlTransport.transportSeq(bytes)
        else { return -1 }
        return jint(seq)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_applyStatus")
    public func swiftCoreApplyStatus(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        cmdSet: jint, cmdId: jint, payload: jbyteArray?, previousJSON: jstring?
    ) -> jstring? {
        var status = AndroidSessionWire.status(fromJSON: swiftString(env, previousJSON) ?? "{}")
        let frame = Duml.Frame(
            sender: 0,
            receiver: 0,
            seq: 0,
            flags: 0,
            cmdSet: UInt8(truncatingIfNeeded: cmdSet),
            cmdId: UInt8(truncatingIfNeeded: cmdId),
            payload: swiftBytes(env, payload) ?? []
        )
        guard CameraStatusDecoder.apply(frame, to: &status) else { return nil }
        return javaString(env, AndroidSessionWire.statusJSON(status))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_hevcCsd")
    public func swiftCoreHevcCsd(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, annexB: jbyteArray?
    ) -> jbyteArray? {
        guard let bytes = swiftBytes(env, annexB),
            let csd = AndroidSessionWire.csd(from: bytes)
        else { return nil }
        return javaByteArray(env, csd)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_hevcNalTypes")
    public func swiftCoreHevcNalTypes(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, annexB: jbyteArray?
    ) -> jstring? {
        javaString(env, AndroidSessionWire.nalTypeSummary(swiftBytes(env, annexB) ?? []))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_hevcIsKeyframe")
    public func swiftCoreHevcIsKeyframe(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, annexB: jbyteArray?
    ) -> jboolean {
        let bytes = swiftBytes(env, annexB) ?? []
        let nals = Hevc.nalUnits(bytes)
        let avc = LiveVideo.detect(nals: nals) == .avc
        for nal in nals {
            guard let first = nal.first else { continue }
            if avc ? Avc.isKeyframeNal(Avc.nalType(first)) : Hevc.isKeyframeNal(Hevc.nalType(first))
            {
                return 1
            }
        }
        return 0
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_depacketizerCreate")
    public func swiftCoreDepacketizerCreate(
        env _: UnsafeMutablePointer<JNIEnv?>, this _: jobject?
    ) -> jlong {
        depacketizerStore.lock.lock()
        defer { depacketizerStore.lock.unlock() }
        let handle = depacketizerStore.next
        depacketizerStore.next += 1
        depacketizerStore.boxes[handle] = HevcDepacketizerBox()
        return handle
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_depacketizerFeed")
    public func swiftCoreDepacketizerFeed(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        handle: jlong, payload: jbyteArray?
    ) -> jbyteArray? {
        guard let bytes = swiftBytes(env, payload) else { return nil }
        depacketizerStore.lock.lock()
        guard let box = depacketizerStore.boxes[handle] else {
            depacketizerStore.lock.unlock()
            return nil
        }
        let completed = box.depacketizer.feed(bytes)
        depacketizerStore.lock.unlock()
        guard let completed else { return nil }
        return javaByteArray(env, completed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_depacketizerDropped")
    public func swiftCoreDepacketizerDropped(
        env _: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, handle: jlong
    ) -> jint {
        depacketizerStore.lock.lock()
        defer { depacketizerStore.lock.unlock() }
        return jint(depacketizerStore.boxes[handle]?.depacketizer.droppedIncomplete ?? 0)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_depacketizerReset")
    public func swiftCoreDepacketizerReset(
        env _: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, handle: jlong
    ) {
        depacketizerStore.lock.lock()
        depacketizerStore.boxes[handle]?.depacketizer.reset()
        depacketizerStore.lock.unlock()
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_depacketizerDestroy")
    public func swiftCoreDepacketizerDestroy(
        env _: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, handle: jlong
    ) {
        depacketizerStore.lock.lock()
        depacketizerStore.boxes.removeValue(forKey: handle)
        depacketizerStore.lock.unlock()
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_gimbalStickEncode")
    public func swiftCoreGimbalStickEncode(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        x: jdouble, y: jdouble, invertPan: jboolean, sensitivity: jint
    ) -> jstring? {
        javaString(
            env,
            AndroidSessionWire.gimbalStickEncode(
                x: Double(x), y: Double(y), invertPan: invertPan != 0,
                sensitivity: Int(sensitivity)))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_camFovChipWrite")
    public func swiftCoreCamFovChipWrite(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, currentFactor: jdouble
    ) -> jstring? {
        javaString(env, AndroidSessionWire.camFovChipWrite(currentFactor: Double(currentFactor)))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_feedWatchdogAction")
    public func swiftCoreFeedWatchdogAction(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, snapshotJSON: jstring?
    ) -> jstring? {
        javaString(
            env,
            AndroidSessionWire.feedWatchdogAction(
                snapshotJSON: swiftString(env, snapshotJSON) ?? "{}"))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_feedWatchdogCreate")
    public func swiftCoreFeedWatchdogCreate(
        env _: UnsafeMutablePointer<JNIEnv?>, this _: jobject?
    ) -> jlong {
        jlong(AndroidSessionWire.feedWatchdogCreate())
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_feedWatchdogTick")
    public func swiftCoreFeedWatchdogTick(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        handle: jlong, snapshotJSON: jstring?
    ) -> jstring? {
        javaString(
            env,
            AndroidSessionWire.feedWatchdogTick(
                handle: Int64(handle),
                snapshotJSON: swiftString(env, snapshotJSON) ?? "{}"))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_feedWatchdogReset")
    public func swiftCoreFeedWatchdogReset(
        env _: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, handle: jlong
    ) {
        AndroidSessionWire.feedWatchdogReset(handle: Int64(handle))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_feedWatchdogDestroy")
    public func swiftCoreFeedWatchdogDestroy(
        env _: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, handle: jlong
    ) {
        AndroidSessionWire.feedWatchdogDestroy(handle: Int64(handle))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_conformPreviewJSON")
    public func swiftCoreConformPreviewJSON(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, request: jstring?
    ) -> jstring? {
        javaString(
            env,
            AndroidSessionWire.conformPreviewJSON(swiftString(env, request) ?? "{}"))
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_validateImportedLut")
    public func swiftCoreValidateImportedLut(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        utf8: jbyteArray?, fileName: jstring?
    ) -> jstring? {
        javaString(
            env,
            LUTLibraryWire.validatedImport(
                utf8: swiftBytes(env, utf8) ?? [],
                fileName: swiftString(env, fileName) ?? "") ?? "")
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packImportedLut")
    public func swiftCorePackImportedLut(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, utf8: jbyteArray?,
        exposureStops: jdouble, colorMode: jint
    ) -> jbyteArray? {
        guard
            let packed = LUTLibraryWire.packedImportedLUT(
                utf8: swiftBytes(env, utf8) ?? [],
                exposureStops: Double(exposureStops),
                colorModeCode: Int(colorMode))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packCreativeLut")
    public func swiftCorePackCreativeLut(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?, title: jstring?,
        exposureStops: jdouble, colorMode: jint
    ) -> jbyteArray? {
        guard
            let packed = LUTLibraryWire.packedCreativeLook(
                swiftString(env, title) ?? "",
                exposureStops: Double(exposureStops),
                colorModeCode: Int(colorMode))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packFalseColorPaint")
    public func swiftCorePackFalseColorPaint(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        scaleOrdinal: jint, colorMode: jint, iso: jint
    ) -> jbyteArray? {
        guard
            let packed = FeedEffectsWire.packedFalseColorPaint(
                scaleOrdinal: Int(scaleOrdinal),
                colorModeCode: Int(colorMode),
                iso: Int(iso))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_packFalseColorWeight")
    public func swiftCorePackFalseColorWeight(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        scaleOrdinal: jint, colorMode: jint, iso: jint
    ) -> jbyteArray? {
        guard
            let packed = FeedEffectsWire.packedFalseColorWeight(
                scaleOrdinal: Int(scaleOrdinal),
                colorModeCode: Int(colorMode),
                iso: Int(iso))
        else { return nil }
        return javaByteArray(env, packed)
    }

    @_cdecl("Java_com_opencapture_openpocketcine_bridge_SwiftCore_feedAssistScalars")
    public func swiftCoreFeedAssistScalars(
        env: UnsafeMutablePointer<JNIEnv?>, this _: jobject?,
        colorMode: jint, iso: jint, highlightIRE: jfloat, midtoneIRE: jfloat
    ) -> jfloatArray? {
        javaFloatArray(
            env,
            FeedEffectsWire.assistScalars(
                colorModeCode: Int(colorMode),
                iso: Int(iso),
                highlightIRE: Double(highlightIRE),
                midtoneIRE: Double(midtoneIRE)))
    }

    private func javaFloatArray(
        _ env: UnsafeMutablePointer<JNIEnv?>, _ values: [Float]
    ) -> jfloatArray? {
        let fns = table(env)
        guard let array = fns.NewFloatArray!(env, jsize(values.count)) else { return nil }
        values.withUnsafeBufferPointer { buffer in
            fns.SetFloatArrayRegion!(env, array, 0, jsize(values.count), buffer.baseAddress)
        }
        return array
    }

#endif
