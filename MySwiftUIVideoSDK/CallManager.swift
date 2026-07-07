import CallKit
import AVFoundation
import ZoomVideoSDK

/// Bridges Apple CallKit to the Zoom Video SDK.
/// One active call at a time (a quickstart, not a full dialer).
/// ponytail: singleton + single-call state; add a call registry if you ever support multiple.
final class CallManager: NSObject, ObservableObject, CXProviderDelegate {
    static let shared = CallManager()

    /// Set when an incoming call is answered. The root view presents `SessionView` for it.
    @Published var pendingSession: PendingSession?

    struct PendingSession: Identifiable, Equatable {
        let id: UUID          // == the CallKit call UUID
        let token: String
        let sessionName: String
        let userName: String
    }

    /// The session's view model, created here (not by the view) so an answered call joins
    /// immediately — even while locked, when SwiftUI won't render the view yet.
    private(set) var activeViewModel: SessionView.ViewModel?

    private let provider: CXProvider
    private let callController = CXCallController()
    // Incoming call details, held from the VoIP push until the user answers.
    private var incoming: [UUID: PendingSession] = [:]

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        // Main queue: the Zoom SDK must be called on the main thread, and all our delegate
        // methods touch it (join/leave/audio session).
        provider.setDelegate(self, queue: .main)
    }

    // MARK: Outgoing (user taps Join in-app)

    func startOutgoingCall(uuid: UUID, handle: String) {
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: handle.isEmpty ? "Video Call" : handle))
        action.isVideo = true
        callController.request(CXTransaction(action: action)) { if let e = $0 { print("startOutgoingCall error: \(e)") } }
    }

    func reportOutgoingConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }

    // MARK: Incoming (VoIP push -> AppDelegate)

    /// MUST be called synchronously from `pushRegistry(_:didReceiveIncomingPushWith:...)` and
    /// `completion()` invoked, or iOS terminates the app.
    func reportIncomingCall(uuid: UUID, session: PendingSession, callerName: String, completion: @escaping () -> Void) {
        incoming[uuid] = session
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName.isEmpty ? "Incoming Call" : callerName)
        update.hasVideo = true
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error { print("reportNewIncomingCall error: \(error)"); self?.incoming[uuid] = nil }
            completion()
        }
    }

    // MARK: Ending

    /// End from inside the app (routes through CallKit so the system UI clears).
    func endCall(uuid: UUID) {
        callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { if let e = $0 { print("endCall error: \(e)") } }
    }

    /// The SDK left the session on its own (remote end / error). Clear the system UI without
    /// re-invoking the end action. ponytail: reportCall(endedAt:) is idempotent enough here.
    func reportCallEnded(uuid: UUID) {
        provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
        incoming[uuid] = nil
        pendingSession = nil
        activeViewModel = nil
    }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        incoming.removeAll()
        pendingSession = nil
        activeViewModel = nil
        ZoomVideoSDK.shareInstance()?.leaveSession(true)
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // Outgoing: the app is already joining the session. Just report progress.
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let session = incoming[action.callUUID] else { action.fail(); return }
        // Join now (not from the view's onAppear) so audio connects even while the device is
        // locked. Delegate is delivered on .main, so we're safely on the main thread here.
        MainActor.assumeIsolated {
            let vm = SessionView.ViewModel()
            vm.jwtToken = session.token
            vm.sessionName = session.sessionName
            vm.userName = session.userName
            vm.callUUID = session.id
            vm.joinUnmutedAudio = true // answer already in-call with audio
            vm.inJWTInput = false      // no JWT prompt for an answered call
            activeViewModel = vm
            pendingSession = session   // SessionView reuses this same vm when it renders
            Task { await vm.joinSession() }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        ZoomVideoSDK.shareInstance()?.leaveSession(true)
        incoming[action.callUUID] = nil
        pendingSession = nil
        activeViewModel = nil
        action.fulfill()
    }

    // Let CallKit own the AVAudioSession; hand it to the SDK once activated.
    // Do NOT call AVAudioSession.setActive yourself — it corrupts SDK audio output.
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        ZoomVideoSDK.shareInstance()?.getAudioHelper()?.setSDKAudioSessionEnv()
    }
}
