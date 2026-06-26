import Foundation
import GroupActivities
import Combine

// MARK: - Twin Share Activity

struct TwinShareActivity: GroupActivity {
    static var activityIdentifier = "com.prvio.app.twin-share"

    var metadata: GroupActivityMetadata {
        var m = GroupActivityMetadata()
        m.title = "Digital Twin PRVIO"
        m.subtitle = "Vizualizează proprietatea împreună"
        m.type = .generic
        return m
    }

    // Payload shared across participants
    var propertyId: String
    var propertyName: String
}

// MARK: - Service

@MainActor
final class GroupActivitiesService: ObservableObject {
    static let shared = GroupActivitiesService()

    @Published var session: GroupSession<TwinShareActivity>?
    @Published var isActive = false
    @Published var participantCount = 0
    @Published var messenger: GroupSessionMessenger?

    private var tasks = Set<Task<Void, Never>>()

    private init() {}

    // Call this to share Twin during a FaceTime call
    func startSharing(propertyId: String, propertyName: String) async {
        let activity = TwinShareActivity(propertyId: propertyId, propertyName: propertyName)
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            try? await activity.activate()
        case .activationDisabled:
            break
        default:
            break
        }
    }

    // Call this on app launch to listen for incoming session invitations
    func listenForSessions() {
        let t = Task {
            for await session in TwinShareActivity.sessions() {
                await self.configure(session: session)
            }
        }
        tasks.insert(t)
    }

    private func configure(session: GroupSession<TwinShareActivity>) async {
        self.session = session
        self.isActive = true
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        let t = Task {
            for await (message, _) in messenger.messages(of: String.self) {
                // Handle real-time messages (camera position, selection, etc.)
                // Extend this block when a shared-state protocol is defined.
                #if DEBUG
                print("[GroupActivities] received message: \(message)")
                #endif
            }
        }
        tasks.insert(t)

        let pt = Task {
            for await participants in session.$activeParticipants.values {
                await MainActor.run { self.participantCount = participants.count }
            }
        }
        tasks.insert(pt)

        session.join()
    }

    func endSession() {
        session?.leave()
        session = nil
        isActive = false
        participantCount = 0
        messenger = nil
    }

    // Send a message to all participants (e.g. camera movement)
    func broadcast(_ message: String) async throws {
        guard let messenger else { return }
        try await messenger.send(message)
    }
}
