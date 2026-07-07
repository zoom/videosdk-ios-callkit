import SwiftUI

@main
struct MySwiftUIVideoSDKApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var callManager = CallManager.shared

    var body: some Scene {
        WindowGroup {
            StartView()
                // Incoming call answered -> present the session for it.
                .fullScreenCover(item: $callManager.pendingSession) { session in
                    SessionView(pending: session)
                }
        }
    }
}
