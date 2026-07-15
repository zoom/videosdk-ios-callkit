import CallKit
import AVFoundation
import ZoomVideoSDK

/// Bridges Apple CallKit to the Zoom Video SDK.
/// One active call at a time; this sample is not a full dialer.
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
    // An answer remains pending until Zoom confirms that the session connected.
    private var pendingAnswerActions: [UUID: CXAnswerCallAction] = [:]
    private var activeCallUUID: UUID?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        // Main queue: the Zoom SDK must be called on the main thread, and all our delegate
        // methods touch it (join/leave/audio session).
        provider.setDelegate(self, queue: .main)
    }

    // MARK: Outgoing (user taps Join in-app)

    @MainActor
    func startOutgoingCall(uuid: UUID, handle: String, viewModel: SessionView.ViewModel) async -> Bool {
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: handle.isEmpty ? "Video Call" : handle))
        action.isVideo = true
        activeCallUUID = uuid
        activeViewModel = viewModel
        let accepted = await withCheckedContinuation { continuation in
            callController.request(CXTransaction(action: action)) { error in
                if let error { print("startOutgoingCall error: \(error)") }
                continuation.resume(returning: error == nil)
            }
        }
        if !accepted { clearCall(uuid: uuid) }
        return accepted
    }

    func reportOutgoingConnected(uuid: UUID) -> Bool {
        guard activeCallUUID == uuid else { return false }
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
        setMuted(uuid: uuid, isMuted: true)
        return true
    }

    func reportIncomingConnected(uuid: UUID) -> Bool {
        guard activeCallUUID == uuid,
              let action = pendingAnswerActions.removeValue(forKey: uuid)
        else {
            reportCallFailed(uuid: uuid)
            return false
        }
        action.fulfill()
        return true
    }

    // MARK: Incoming (VoIP push -> AppDelegate)

    /// MUST be called synchronously from `pushRegistry(_:didReceiveIncomingPushWith:...)` and
    /// `completion()` invoked, or iOS terminates the app.
    func reportIncomingCall(uuid: UUID, session: PendingSession, callerName: String, completion: @escaping () -> Void) {
        let isExistingCall = incoming[uuid] != nil || activeCallUUID == uuid
        if !isExistingCall { incoming[uuid] = session }
        let update = callUpdate(handle: callerName.isEmpty ? "Incoming Call" : callerName)
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("reportNewIncomingCall error: \(error)")
                    if !isExistingCall { self?.incoming[uuid] = nil }
                }
                completion()
            }
        }
    }

    // MARK: Ending

    /// End from inside the app (routes through CallKit so the system UI clears).
    func endCall(uuid: UUID) {
        callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
            guard let error else { return }
            print("endCall error: \(error)")
            DispatchQueue.main.async {
                if self?.activeCallUUID == uuid {
                    ZoomVideoSDK.shareInstance()?.leaveSession(true)
                }
                self?.reportCallFailed(uuid: uuid)
            }
        }
    }

    func setMuted(uuid: UUID, isMuted: Bool) {
        let action = CXSetMutedCallAction(call: uuid, muted: isMuted)
        callController.request(CXTransaction(action: action)) { error in
            if let error { print("setMuted error: \(error)") }
        }
    }

    /// The SDK left the session on its own (remote end / error). Clear the system UI without
    /// re-invoking the end action. ponytail: reportCall(endedAt:) is idempotent enough here.
    func reportCallEnded(uuid: UUID) {
        pendingAnswerActions.removeValue(forKey: uuid)?.fail()
        provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
        clearCall(uuid: uuid)
    }

    func reportCallFailed(uuid: UUID) {
        pendingAnswerActions.removeValue(forKey: uuid)?.fail()
        provider.reportCall(with: uuid, endedAt: nil, reason: .failed)
        clearCall(uuid: uuid)
    }

    private func clearCall(uuid: UUID) {
        incoming[uuid] = nil
        if pendingSession?.id == uuid { pendingSession = nil }
        if activeCallUUID == uuid {
            activeCallUUID = nil
            activeViewModel = nil
        }
    }

    private func callUpdate(handle: String? = nil) -> CXCallUpdate {
        let update = CXCallUpdate()
        if let handle { update.remoteHandle = CXHandle(type: .generic, value: handle) }
        update.hasVideo = true
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        pendingAnswerActions.values.forEach { $0.fail() }
        pendingAnswerActions.removeAll()
        incoming.removeAll()
        pendingSession = nil
        activeCallUUID = nil
        activeViewModel = nil
        ZoomVideoSDK.shareInstance()?.leaveSession(true)
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportCall(with: action.callUUID, updated: callUpdate(handle: action.handle.value))
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let session = incoming[action.callUUID] else { action.fail(); return }
        guard activeCallUUID == nil else {
            action.fail()
            reportCallFailed(uuid: action.callUUID)
            return
        }
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
            activeCallUUID = action.callUUID
            activeViewModel = vm
            pendingSession = session   // SessionView reuses this same vm when it renders
            pendingAnswerActions[action.callUUID] = action
            Task { await vm.joinSession() }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        pendingAnswerActions.removeValue(forKey: action.callUUID)?.fail()
        if activeCallUUID == action.callUUID {
            ZoomVideoSDK.shareInstance()?.leaveSession(true)
        }
        clearCall(uuid: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard activeCallUUID == action.callUUID,
              let audioHelper = ZoomVideoSDK.shareInstance()?.getAudioHelper(),
              let myUser = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf()
        else {
            action.fail()
            return
        }

        let result = action.isMuted ? audioHelper.muteAudio(myUser) : audioHelper.unmuteAudio(myUser)
        guard result == .Errors_Success else {
            print("setMuted SDK error: \(result.rawValue)")
            action.fail()
            return
        }
        MainActor.assumeIsolated { activeViewModel?.audioOn = !action.isMuted }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fail()
        guard let callAction = action as? CXCallAction,
              action is CXStartCallAction || action is CXAnswerCallAction
        else { return }

        pendingAnswerActions.removeValue(forKey: callAction.callUUID)
        if activeCallUUID == callAction.callUUID {
            ZoomVideoSDK.shareInstance()?.leaveSession(true)
        }
        provider.reportCall(with: callAction.callUUID, endedAt: nil, reason: .failed)
        clearCall(uuid: callAction.callUUID)
    }

    // Let CallKit own the AVAudioSession; hand it to the SDK once activated.
    // Do NOT call AVAudioSession.setActive yourself — it corrupts SDK audio output.
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        ZoomVideoSDK.shareInstance()?.getAudioHelper()?.setSDKAudioSessionEnv()
    }
}
