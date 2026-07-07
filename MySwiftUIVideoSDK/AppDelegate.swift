import UIKit
import PushKit

/// Present only for PushKit — SwiftUI has no app delegate, but VoIP pushes must be handled at
/// the process level. Wired in via `@UIApplicationDelegateAdaptor` in the App struct.
final class AppDelegate: NSObject, UIApplicationDelegate, PKPushRegistryDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        return true
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        // ponytail: just log it — a real app POSTs this to your backend. Feed it to Scripts/send_voip_push.sh.
        print("VoIP device token: \(token)")
    }

    /// iOS 13+: for EVERY VoIP push we must report a call to CallKit in this call and invoke
    /// `completion()`, or the app is killed. Bad/empty payload -> report then immediately end.
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        let uuid = UUID()
        let session = CallManager.PendingSession(
            id: uuid,
            token: dict["token"] as? String ?? "",
            sessionName: dict["sessionName"] as? String ?? "",
            userName: dict["userName"] as? String ?? "Me"
        )
        CallManager.shared.reportIncomingCall(uuid: uuid, session: session, callerName: dict["callerName"] as? String ?? "") {
            if session.token.isEmpty || session.sessionName.isEmpty {
                CallManager.shared.reportCallEnded(uuid: uuid) // nothing to join
            }
            completion()
        }
    }
}
