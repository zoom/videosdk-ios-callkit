# Zoom Video SDK iOS CallKit Sample

This sample demonstrates the native call lifecycle with SwiftUI, CallKit,
PushKit, APNs, and the Zoom Video SDK, including outgoing calls, incoming VoIP
calls, system audio ownership, mute synchronization, and session cleanup.

The app UI is intentionally minimal so the project stays focused on the
CallKit integration and can be used as a reference when adding native calling
to another Zoom Video SDK application.

Use of this sample is subject to the Zoom
[Terms of Use](https://explore.zoom.us/en/video-sdk-terms/).

## Requirements

- A Mac with Xcode and its command-line tools installed
- An iPhone or iPad running iOS 18 or later
- A Zoom Video SDK account with an SDK Key and SDK Secret
- A paid Apple Developer Program membership for device signing and VoIP pushes
- An APNs authentication key (`.p8`) for incoming-call testing
- Camera, microphone, and network access on the test device

The project uses Swift Package Manager. Xcode resolves the pinned
`ZoomVideoSDK-iOS` package when the project opens. Update the package version
deliberately rather than automatically changing it before the first build.

> Incoming VoIP pushes require a physical device. The Simulator can be useful
> for UI work, but it cannot validate the complete PushKit and CallKit flow.

## 1. Open the project

From the repository root:

```bash
open MySwiftUIVideoSDK.xcodeproj
```

Wait for Xcode to resolve the Swift package. If resolution does not start,
select **File → Packages → Resolve Package Versions**.

The app target currently has an iOS 18 deployment target. To support older iOS
versions, lower the deployment target only after verifying that the selected
Zoom Video SDK release supports them.

## 2. Configure Apple signing

In Xcode:

1. Select the `MySwiftUIVideoSDK` project in the navigator.
2. Select the `MySwiftUIVideoSDK` app target.
3. Open **Signing & Capabilities**.
4. Set a unique Bundle Identifier, such as `com.example.videosdk.callkit`.
5. Select your paid Apple Developer team.
6. Enable **Automatically manage signing**, or select development and
   distribution profiles that contain the required push entitlement.
7. Confirm that **Push Notifications** is listed as a capability. Add it with
   **+ Capability** if it is missing.

The repository already contains these required settings:

- `audio`, `voip`, and `remote-notification` background modes in
  `MySwiftUIVideoSDK/Info.plist`
- The `aps-environment` entitlement in
  `MySwiftUIVideoSDK/MySwiftUIVideoSDK.entitlements`
- `development` APNs for Debug and `production` APNs for Release
- Camera, microphone, and Bluetooth usage descriptions

If Push Notifications was enabled after a provisioning profile was created,
regenerate or refresh the profile so it includes the APS entitlement. The
Bundle Identifier used by Xcode, the Apple Developer App ID, the provisioning
profile, and the `BUNDLE_ID` used by the push script must be identical.
When managing identifiers manually, register an explicit App ID for that
Bundle Identifier and enable Push Notifications on it.

## 3. Get Zoom Video SDK credentials

Create or open a Video SDK app in the Zoom developer portal and copy its
**SDK Key** and **SDK Secret**. These are not the Video SDK API Key and API
Secret; API credentials do not authorize a client to join an SDK session. See
[Get Video SDK credentials](https://developers.zoom.us/docs/video-sdk/get-credentials/).

Do not put the SDK Secret in the iOS app. The included generator is only a
local development tool. A production backend should hold the secret and issue
short-lived session tokens to authenticated clients.

## 4. Create the local environment file

Create `Scripts/.env` from the repository root. The file is ignored by Git.
Use unquoted values:

```dotenv
# Zoom Video SDK token generation
SESSION_NAME=TestSession12345
ROLE=1
SDK_KEY=your_video_sdk_key
SDK_SECRET=your_video_sdk_secret

# APNs VoIP push sending
AUTH_KEY_PATH=/absolute/path/to/AuthKey_XXXXXXXXXX.p8
KEY_ID=XXXXXXXXXX
TEAM_ID=YYYYYYYYYY
BUNDLE_ID=com.example.videosdk.callkit
APNS_ENV=sandbox

# Display name used by the receiving device
USER_NAME=Receiver
```

Field reference:

| Variable | Purpose |
| --- | --- |
| `SESSION_NAME` | Session identifier. It must match the `tpc` claim in the generated Zoom JWT. |
| `ROLE` | `1` for the session host, `0` for a participant. |
| `SDK_KEY` / `SDK_SECRET` | Video SDK credentials used only by the local JWT generator. |
| `AUTH_KEY_PATH` | Absolute path to the APNs `.p8` private key. |
| `KEY_ID` | Identifier shown for the APNs key in the Apple Developer portal. |
| `TEAM_ID` | Apple Developer Team ID, not the team display name. |
| `BUNDLE_ID` | Exact Xcode Bundle Identifier. Do not append `.voip`; the script does that. |
| `APNS_ENV` | `sandbox` for Debug/development builds or `prod` for distribution builds. |
| `USER_NAME` | Zoom display name for the device answering the incoming call. |

Keep `Scripts/.env`, the `.p8` file, SDK secrets, generated JWTs, and device
tokens out of source control and issue trackers.

## 5. Generate a Zoom session JWT

Run:

```bash
swift Scripts/JWTGenerator.swift
```

The command reads `SESSION_NAME`, `ROLE`, `SDK_KEY`, and `SDK_SECRET` from
`Scripts/.env` and prints one JWT. The generated token is valid for two hours.

You can also pass the values directly:

```bash
swift Scripts/JWTGenerator.swift TestSession12345 1 your_sdk_key your_sdk_secret
```

Command-line credentials can be retained in shell history, so the `.env`
method is preferable for local development.

The session name in the app and the session name used to generate the token
must match. Zoom uses that name to create a new session or join an existing
one. See [Zoom Video SDK sessions](https://developers.zoom.us/docs/video-sdk/ios/sessions/).

## 6. Configure and test an outgoing call

For the normal in-app join flow, open
`MySwiftUIVideoSDK/SessionView+Extension.swift` and set:

```swift
var jwtToken = ""
var sessionName = "TestSession12345"
var userName = "Alice"
```

Leave `jwtToken` empty to paste the generated token at runtime. For a temporary
local test you may assign the token directly, but it expires and should never
be committed.

Then:

1. Select your physical device as the run destination.
2. Build and run the app.
3. Allow camera and microphone access when prompted.
4. Tap **Join Session**.
5. Paste the generated Zoom session JWT and tap **Join**.

The app asks CallKit to start an outgoing system call before joining Zoom. The
call becomes connected only after Zoom reports that the session joined. It
starts muted; use the in-app audio control to unmute through CallKit.

To test remote video, join the same session from a second Video SDK client
using a token generated from the same SDK credentials and session name.

## 7. Configure APNs for incoming calls

### Create an APNs authentication key

1. Sign in to **Certificates, Identifiers & Profiles** in the Apple Developer
   portal.
2. Open **Keys** and create a key with **Apple Push Notifications service
   (APNs)** enabled.
3. Download the `.p8` file. Apple allows it to be downloaded only once.
4. Record the Key ID and Team ID.
5. Put the absolute `.p8` path and identifiers in `Scripts/.env`.

An APNs signing key works with both development and production APNs. Protect it
like a password and revoke it if it is exposed. See
[Communicate with APNs using authentication tokens](https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/).

### Obtain the VoIP device token

1. Build and run the signed app on a physical device.
2. Open the Xcode debug console.
3. Find and copy the complete line value after:

   ```text
   VoIP device token: <hexadecimal token>
   ```

Use the most recently logged token. A token belongs to one app installation,
device, Bundle Identifier, and APNs environment, and it may change after the
app is reinstalled or reprovisioned. A production app must upload this token to
its backend and delete it there when PushKit invalidates it.

## 8. Send a test incoming call

Generate a fresh Zoom session JWT for the session that the receiving device
should join, then run:

```bash
swift Scripts/VoIPPush.swift <voip-device-token> TestSession12345 <zoom-session-jwt> "Alice"
```

Example shape:

```bash
swift Scripts/VoIPPush.swift 6a1f...c9 TestSession12345 eyJ0eXAi... "Alice"
```

The arguments are:

1. VoIP device token from the Xcode console
2. Zoom session name
3. Zoom Video SDK session JWT for that exact session name
4. Optional caller name shown by CallKit

The script:

- Authenticates to APNs with the `.p8` key
- Sends to the `<BUNDLE_ID>.voip` topic
- Uses `sandbox` or `prod` according to `APNS_ENV`
- Creates a unique CallKit UUID
- Sets APNs expiry to zero so a stale call is not delivered later
- Includes the Zoom session information required when the call is answered

Success prints:

```text
Sent (200)
```

The device should display the native incoming-call screen when the app is
foregrounded, backgrounded, or relaunched by PushKit. A user force-quit can
prevent delivery until the app is opened again. Answering starts the Zoom join;
CallKit remains in the connecting state until Zoom confirms the session joined.
Declining or ending the system call leaves or cancels the Zoom session.

Use this environment mapping:

| Installed build | APS entitlement | `APNS_ENV` |
| --- | --- | --- |
| Xcode Debug/development profile | `development` | `sandbox` |
| TestFlight or App Store distribution | `production` | `prod` |

The local script is a test tool, not a production call-signaling service.
Apple requires apps receiving VoIP pushes to report the call through CallKit;
see [Responding to VoIP notifications from PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit).

## Call flow

### Outgoing

1. The user taps **Join Session** and supplies a Zoom JWT.
2. `CallManager` requests a `CXStartCallAction`.
3. After CallKit accepts the action, the app joins the Zoom session.
4. Zoom reports the session joined.
5. The app reports the outgoing call as connected.
6. CallKit owns audio activation and mute actions until the call ends.

### Incoming

1. APNs wakes the app with a PushKit VoIP notification.
2. `AppDelegate` validates the call UUID and Zoom session data.
3. `CallManager` immediately reports the incoming call to CallKit.
4. When the user answers, the app begins joining Zoom.
5. The answer action is fulfilled only after Zoom reports a successful join.
6. Ending the call from CallKit or the app leaves the Zoom session.

## Troubleshooting

### Xcode cannot create a provisioning profile

- Confirm the selected team has a paid Apple Developer membership.
- Use a Bundle Identifier that belongs to that team.
- Enable Push Notifications for the App ID.
- Refresh profiles after changing App ID capabilities.
- With manual signing, select profiles containing the APS entitlement for both
  Debug and Release.

### No VoIP device token appears

- Use a physical device, not the Simulator.
- Confirm the app is signed and the Push Notifications capability is enabled.
- Launch the app while the device has network access.
- Search the Xcode console for `VoIP device token`.
- Delete and reinstall the app after correcting signing or capability settings.

### APNs returns `BadDeviceToken`

- Match `APNS_ENV` to the installed build.
- Copy the complete current token without spaces or angle brackets.
- Do not reuse a token from another Bundle Identifier or app installation.

### APNs returns `DeviceTokenNotForTopic` or `TopicDisallowed`

- Make `BUNDLE_ID` exactly match the signed app's Bundle Identifier.
- Do not include `.voip` in `BUNDLE_ID`; the script appends it.
- Confirm Push Notifications is enabled for the App ID and provisioning profile.

### APNs returns an authentication error

- Check `AUTH_KEY_PATH`, `KEY_ID`, and `TEAM_ID`.
- Confirm the key has APNs enabled and has not been revoked.
- Ensure the `.p8` file is intact and readable by the current user.

### The call rings but Zoom does not join

- Generate a fresh Zoom session JWT.
- Ensure the command's session name matches the JWT `tpc` value.
- Use Video SDK credentials, not Video SDK API credentials.
- Check the Xcode console for `ZoomVideoSDKError` values.
- Confirm the device can reach Zoom over the current network.

### The call joins without remote video or audio

- A second client must join the same Zoom session to provide remote media.
- Grant camera and microphone permissions in iOS Settings.
- Use the in-app microphone control; mute state is routed through CallKit.
- Check whether Bluetooth or another system call owns the audio route.

### A push succeeds but no incoming UI appears

- Confirm the target device is running the app signed for the same environment
  used by the script.
- Check device logs for payload validation or CallKit reporting failures.
- Verify the payload has a UUID, token, and session name; the included script
  supplies all three.
- Always use the latest device token printed by the current installation.

## Production considerations

The included flow intentionally keeps local testing small. Before using it in
production:

- Generate Zoom session JWTs on your backend; never ship the SDK Secret.
- Store the APNs `.p8` key only on a secured backend.
- Register, refresh, and invalidate each user's VoIP device tokens server-side.
- Authorize callers and recipients before creating a call.
- Send only the minimum call metadata in the VoIP payload. Fetch session
  credentials securely when the user answers instead of embedding a Zoom JWT.
- Map each backend call identifier to one stable CallKit UUID.
- Maintain a real-time signaling connection for accept, reject, cancel, busy,
  timeout, and remote-end events.
- Rotate or revoke credentials immediately if they are exposed.

## Optional command-line verification

Type-check the two local scripts:

```bash
swiftc -typecheck Scripts/JWTGenerator.swift
swiftc -typecheck Scripts/VoIPPush.swift
```

Compile the iOS app without signing:

```bash
xcodebuild \
  -project MySwiftUIVideoSDK.xcodeproj \
  -scheme MySwiftUIVideoSDK \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For additional script details, see [Scripts/README.md](Scripts/README.md).

## Screenshots

### Start view

<img src="https://github.com/user-attachments/assets/47e3e000-01fc-4194-a5fa-57f97afb65ce" width="320" alt="Start view">
<img src="https://github.com/user-attachments/assets/b6efc031-9002-4bf7-a8f4-29bff8326252" width="320" alt="Start view session prompt">

### Session view

<img src="https://github.com/user-attachments/assets/eac551f4-88c6-41e1-b58e-2d2d0497f405" width="320" alt="Video SDK session view">
<img src="https://github.com/user-attachments/assets/d3dc5b3f-2c39-4943-9f5e-1ea4c2579900" width="320" alt="Video SDK session controls">

## Support

For Zoom Video SDK help, use
[Zoom Developer Support](https://developers.zoom.us/support/) or the
[Zoom Developer Forum](https://devforum.zoom.us/).
