import Foundation
import OpenPocketViewCore

struct FrameioProjectListing: Equatable, Sendable {
    var accountID: String
    var workspaceID: String
    var workspaceName: String
    var projects: [FrameioProject]
}

struct FrameioDestination: Codable, Equatable {
    var accountID: String
    var workspaceID: String?
    var projectID: String
    var projectName: String
    var folderID: String

    private static let userDefaultsName = "opc.frameio.destination.v1"

    static var loaded: FrameioDestination? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsName) else { return nil }
        return try? JSONDecoder().decode(FrameioDestination.self, from: data)
    }

    static func persist(_ destination: FrameioDestination?) {
        if let destination, let data = try? JSONEncoder().encode(destination) {
            UserDefaults.standard.set(data, forKey: userDefaultsName)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsName)
        }
    }
}

struct MediaDeliveryUploadOptions: Sendable {
    var filename: String
    var bakeLUT: Bool
    var cube: CubeLUT?
    var metadata: MediaClipDeliveryMetadata?
    var forceReupload: Bool
}

extension AppModel {
    var frameioConfiguration: FrameioConfiguration? { FrameioConfig.configuration }
    var isFrameioConfigured: Bool { frameioConfiguration != nil }
    var isFrameioConnected: Bool { isFrameioConfigured && FrameioTokenStore.isConnected }

    func connectFrameio() async throws {
        guard let config = frameioConfiguration else { throw FrameioError.notConfigured }
        frameioConnecting = true
        defer { frameioConnecting = false }
        _ = try await FrameioAuthCoordinator(config: config).signIn()
        frameioUser = try? await FrameioService(config: config).currentUser()
    }

    func disconnectFrameio() {
        FrameioTokenStore.clear()
        frameioUser = nil
        FrameioDestination.persist(nil)
    }

    func loadFrameioUserIfNeeded() async {
        guard isFrameioConnected, frameioUser == nil, let config = frameioConfiguration else {
            return
        }
        frameioUser = try? await FrameioService(config: config).currentUser()
    }

    func loadFrameioProjectListing() async throws -> FrameioProjectListing {
        guard let config = frameioConfiguration else { throw FrameioError.notConfigured }
        if !isFrameioConnected { try await connectFrameio() }
        let service = FrameioService(config: config)
        if frameioUser == nil { frameioUser = try? await service.currentUser() }
        guard let account = try await service.accounts().first else { throw FrameioError.noProject }
        guard let workspace = try await service.workspaces(accountID: account.id).first else {
            throw FrameioError.noProject
        }
        let projects = try await service.projects(
            accountID: account.id, workspaceID: workspace.id)
        return FrameioProjectListing(
            accountID: account.id,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            projects: projects)
    }

    func createFrameioProject(
        name: String, accountID: String, workspaceID: String
    ) async throws -> FrameioProject {
        guard let config = frameioConfiguration else { throw FrameioError.notConfigured }
        if !isFrameioConnected { try await connectFrameio() }
        return try await FrameioService(config: config).createProject(
            accountID: accountID, workspaceID: workspaceID, name: name)
    }

    func persistFrameioDestination(
        project: FrameioProject, accountID: String, workspaceID: String
    ) {
        guard let folderID = project.rootFolderID else { return }
        FrameioDestination.persist(
            FrameioDestination(
                accountID: accountID,
                workspaceID: workspaceID,
                projectID: project.id,
                projectName: project.name,
                folderID: folderID))
    }

    func uploadFileToFrameio(
        sourceURL: URL,
        filename: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let config = frameioConfiguration else { throw FrameioError.notConfigured }
        if !isFrameioConnected { try await connectFrameio() }
        let service = FrameioService(config: config)
        if frameioUser == nil { frameioUser = try? await service.currentUser() }
        let destination = try await resolveFrameioDestination(using: service)
        let size =
            (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size]
            as? NSNumber)?.intValue ?? 0
        let mediaType = FrameioMediaType.forFilename(filename)
        _ = try await service.upload(
            fileURL: sourceURL, name: filename, mediaType: mediaType,
            fileSize: size, accountID: destination.accountID, folderID: destination.folderID
        ) { fraction in
            onProgress?(fraction)
        }
    }

    private func resolveFrameioDestination(using service: FrameioService) async throws
        -> FrameioDestination
    {
        if let saved = FrameioDestination.loaded { return saved }
        guard let account = try await service.accounts().first else { throw FrameioError.noProject }
        guard let workspace = try await service.workspaces(accountID: account.id).first else {
            throw FrameioError.noProject
        }
        guard
            let project = try await service.projects(
                accountID: account.id, workspaceID: workspace.id
            ).first,
            let folderID = project.rootFolderID
        else { throw FrameioError.noProject }
        let destination = FrameioDestination(
            accountID: account.id, workspaceID: workspace.id, projectID: project.id,
            projectName: project.name, folderID: folderID)
        FrameioDestination.persist(destination)
        return destination
    }
}
