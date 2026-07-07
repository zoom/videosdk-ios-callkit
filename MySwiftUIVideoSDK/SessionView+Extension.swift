import SwiftUI
import ZoomVideoSDK

extension SessionView {
    @MainActor
    class ViewModel: NSObject, ObservableObject, @preconcurrency ZoomVideoSDKDelegate {
        // Error popup
        @Published var errorTitle: String = "Error"
        var errorMessage: String = "Message"

        // Local user
        @Published var userInputJWT = ""
        @Published var shouldJoin = false
        @MainActor weak var localView: UIView?
        @Published var joinSessionFailed: Bool = false
        @Published var inJWTInput: Bool = true
        @Published var inSession: Bool = false
        @Published var leftSession: Bool = false
        @Published var videoOn: Bool = false
        @Published var audioOn: Bool = false

        // Remote users
        @Published var remoteUsers: [ZoomVideoSDKUser] = []

        // MARK: Session Information

        /*
         TODO: Enter the following variables needed to initialize the VSDK and to start/join a session
         You should sign your JWT with a backend service in a production use-case. For faster JWT generation, you can navigate checkout the JWTGenerator.swift under Script folder and its README for more details on how to consume it.
         Once you got the token, you can simple copy and paste it below.
         Ensure that the sessionName matches the session name used to generate the JWT Token.
         */
        var jwtToken = "" // Leave this as empty if you choose to copy and paste your generated JWT token directly in the sample app's alert box after clicking on "Join Session"
        var sessionName = "" // Also known as tpc in JWT
        var userName = "" // Display name
        let sessionPassword: String = "" // If needed

        // CallKit: the system call this session is tied to. Set for both incoming (from the
        // answered call) and outgoing (created on join). nil until a call exists.
        var callUUID: UUID?
        var joinUnmutedAudio = false // incoming calls answer already in-call with audio connected
        private var isOutgoingCall = false // this session initiated the CallKit call (vs. answered)

        @MainActor func attachLocalVideo(to view: UIView) {
            localView = view
        }

        @MainActor func updateLocalVideo(to _: UIView) {
            guard let myUserVideoCanvas = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf()?.getVideoCanvas(), let myVideoIsOn = myUserVideoCanvas.videoStatus()?.on else { return }
            if myVideoIsOn {
                myUserVideoCanvas.subscribe(with: localView, aspectMode: .panAndScan, andResolution: ._Auto)
            } else {
                myUserVideoCanvas.unSubscribe(with: localView)
            }
        }

        @MainActor func attachRemoteUserVideo(index: Int, to view: UIView) {
            guard let index = remoteUsers.indices.first(where: { $0 == index }) else { return }
            if let currentUserVideoCanvas = remoteUsers[index].getVideoCanvas(), let videoStatus = currentUserVideoCanvas.videoStatus() {
                if videoStatus.on {
                    currentUserVideoCanvas.subscribe(with: view, aspectMode: .panAndScan, andResolution: ._Auto)
                } else {
                    currentUserVideoCanvas.unSubscribe(with: view)
                }
            }
        }

        @MainActor func updateRemoteVideo(to view: UIView, index: Int) {
            guard let index = remoteUsers.indices.first(where: { $0 == index }) else { return }
            if let currentUserVideoCanvas = remoteUsers[index].getVideoCanvas(), let videoStatus = currentUserVideoCanvas.videoStatus() {
                if videoStatus.on {
                    currentUserVideoCanvas.subscribe(with: view, aspectMode: .panAndScan, andResolution: ._Auto)
                } else {
                    currentUserVideoCanvas.unSubscribe(with: view)
                }
            }
        }

        func joinSession() async {
            // Outgoing call: no CallKit call exists yet, so report one to the system.
            // (Incoming calls arrive with callUUID already set by CallManager.)
            if callUUID == nil {
                let uuid = UUID()
                callUUID = uuid
                isOutgoingCall = true
                CallManager.shared.startOutgoingCall(uuid: uuid, handle: sessionName)
            }
            ZoomVideoSDK.shareInstance()?.delegate = self
            let sessionContext = ZoomVideoSDKSessionContext()
            sessionContext.token = jwtToken.isEmpty ? userInputJWT : jwtToken
            sessionContext.sessionName = sessionName
            sessionContext.userName = userName
            let videoOption = ZoomVideoSDKVideoOptions()
            videoOption.localVideoOn = true
            sessionContext.videoOption = videoOption
            let audioOtion = ZoomVideoSDKAudioOptions()
            // Incoming calls answer in-call (audio connected, unmuted); otherwise keep the
            // original behavior (not connected, muted) until the user taps unmute.
            audioOtion.connect = joinUnmutedAudio
            audioOtion.mute = !joinUnmutedAudio
            sessionContext.audioOption = audioOtion
            if !sessionPassword.isEmpty {
                sessionContext.sessionPassword = sessionPassword
            }
            // Join Session
            if let session = ZoomVideoSDK.shareInstance()?.joinSession(sessionContext) {
                print("Session object: \(session)")
            } else {
                print("Join session failed")
                endCallKitCall()
                DispatchQueue.main.async {
                    self.joinSessionFailed = true
                }
            }
        }

        func onError(_ ErrorType: ZoomVideoSDKError, detail details: Int) {
            print("Error: \(ErrorType.rawValue) (\(details))")
            if !inSession {
                endCallKitCall()
                joinSessionFailed = true
                leftSession = true
                errorMessage = "Failed to join session with error: \(ErrorType.rawValue)"
            }
        }

        func onSessionJoin() {
            // Session joined successfully.
            print("Session joined")
            inSession = true
            if joinUnmutedAudio { audioOn = true } // mic button reflects the connected audio
            // Only outgoing calls need connect confirmation; answered calls are already connected.
            if isOutgoingCall, let uuid = callUUID { CallManager.shared.reportOutgoingConnected(uuid: uuid) }
        }

        func onUserJoin(_: ZoomVideoSDKUserHelper?, users: [ZoomVideoSDKUser]?) {
            // Get remote user
            if let userArray = users, let myself = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf() {
                for user in userArray {
                    if user.getID() != myself.getID() {
                        remoteUsers.append(user)
                    }
                }
            }
        }

        func onUserLeave(_: ZoomVideoSDKUserHelper?, users: [ZoomVideoSDKUser]?) {
            // Get remote user
            if let userArray = users, let myself = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf() {
                for user in userArray {
                    if user.getID() != myself.getID() {
                        remoteUsers.removeAll { remoteUser in
                            remoteUser.getID() == user.getID()
                        }
                    }
                }
            }
        }

        func onUserVideoStatusChanged(_: ZoomVideoSDKVideoHelper?, user: [ZoomVideoSDKUser]?) {
            if let userArray = user, let myself = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf() {
                for user in userArray {
                    if user.getID() == myself.getID() {
                        if let myUserVideoCanvas = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf()?.getVideoCanvas(), let myVideoIsOn = myUserVideoCanvas.videoStatus()?.on {
                            if myVideoIsOn {
                                Task(priority: .background) {
                                    await MainActor.run {
                                        self.videoOn = true
                                    }
                                }
                            } else {
                                Task(priority: .background) {
                                    await MainActor.run {
                                        videoOn = false
                                    }
                                }
                            }
                        }
                    }

                    // Get remote user
                    if user.getID() != myself.getID(), let remoteUserIndex = remoteUsers.firstIndex(where: { currentUser in
                        currentUser.getID() == user.getID()
                    }) {
                        remoteUsers[remoteUserIndex] = user
                    }
                }
            }
        }

        func onSessionLeave() {
            endCallKitCall()
            leftSession = true
        }

        // Local user - toggle video on/off
        func toggleVideo() {
            if let usersVideoCanvas = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf()?.getVideoCanvas(),
               // Get ZoomVideoSDKVideoHelper to control video
               let videoHelper = ZoomVideoSDK.shareInstance()?.getVideoHelper()
            {
                if let myVideoIsOn = usersVideoCanvas.videoStatus()?.on,
                   myVideoIsOn == true
                {
                    Task(priority: .background) {
                        await MainActor.run {
                            let error = videoHelper.stopVideo()
                            print("Stop error: \(error.rawValue)")
                        }
                    }
                } else {
                    Task(priority: .background) {
                        await MainActor.run {
                            let error = videoHelper.startVideo()
                            print("Start error: \(error.rawValue)")
                        }
                    }
                }
            }
        }

        // Local user - toggle audio mic unmute/mute
        func toggleAudio() {
            let myUser = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf()
            // Get the user's audio status
            if let audioStatus = myUser?.audioStatus(),
               // Get ZoomVideoSDKAudioHelper to control audio
               let audioHelper = ZoomVideoSDK.shareInstance()?.getAudioHelper()
            {
                // Check if the user's audio type is none - Not connected yet
                if audioStatus.audioType == .none {
                    Task(priority: .background) {
                        await MainActor.run {
                            audioHelper.startAudio()
                            audioOn = true
                        }
                    }
                } else {
                    // Audio is connected - Toggle audio based on mute status
                    if audioStatus.isMuted {
                        Task(priority: .background) {
                            await MainActor.run {
                                let error = audioHelper.unmuteAudio(myUser)
                                print("Unmute error: \(error.rawValue)")
                                audioOn = true
                            }
                        }
                    } else {
                        Task(priority: .background) {
                            await MainActor.run {
                                let error = audioHelper.muteAudio(myUser)
                                print("Mute error: \(error.rawValue)")
                                audioOn = false
                            }
                        }
                    }
                }
            }
        }

        // Clear the reported CallKit call when a join never completes, so the system doesn't
        // show a phantom "connecting" call.
        func endCallKitCall() {
            if let uuid = callUUID { CallManager.shared.reportCallEnded(uuid: uuid); callUUID = nil }
        }

        func leaveSession() {
            // Route through CallKit when a system call exists so its UI clears; the
            // CXEndCallAction handler performs the actual leaveSession.
            if let uuid = callUUID {
                CallManager.shared.endCall(uuid: uuid)
            } else {
                ZoomVideoSDK.shareInstance()?.leaveSession(true)
            }
        }
    }
}
