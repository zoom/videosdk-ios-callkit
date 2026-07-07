# Zoom VideoSDK iOS SwiftUI Demo

Use of this sample app is subject to our [Terms of Use](https://explore.zoom.us/en/video-sdk-terms/).

The Zoom Video SDK for iOS lets you build custom video meeting applications with access to raw video and audio data, enabling highly-interactive, custom user experiences. This repository contains a completed sample app written in Swift with SwiftUI. 

Note: Under "Package Dependencies", right click it and select "Update to Latest Package Versions" to ensure you stay on the latest ZoomVideoSDK-iOS SPM version.

## Screenshots

<p>Start View</p>
<img src="https://github.com/user-attachments/assets/47e3e000-01fc-4194-a5fa-57f97afb65ce" width="320">
<img src="https://github.com/user-attachments/assets/b6efc031-9002-4bf7-a8f4-29bff8326252" width="320">

<br><br>

<p>Session View</p>

<img src="https://github.com/user-attachments/assets/eac551f4-88c6-41e1-b58e-2d2d0497f405" width="320">
<img src="https://github.com/user-attachments/assets/d3dc5b3f-2c39-4943-9f5e-1ea4c2579900" width="320">


## Features
This repository demonstrates the basic capabilities of the Video SDK.
- Creating/joining a session
- Starting/stopping video
- Muting/unmuting audio
- Native call experience via Apple [CallKit](https://developer.apple.com/documentation/callkit) — outgoing calls (system audio priority + Recents) and incoming calls (native ring UI) driven by VoIP pushes

## CallKit

Joining a session reports an outgoing system call; a VoIP push rings a native incoming call that joins the session on answer. The audio session is handed to the SDK in `CXProvider` `didActivate` via `setSDKAudioSessionEnv()` — see `CallManager.swift` and `AppDelegate.swift`.

Incoming calls need an APNs VoIP push. There's no backend, so use `Scripts/VoIPPush.swift` to fire one from your machine — see [Scripts/README.md](Scripts/README.md).

**Requirements (already configured in the project):**
- `UIBackgroundModes`: `audio`, `voip`, `remote-notification` (`MySwiftUIVideoSDK/Info.plist`)
- Push Notifications capability / `aps-environment` (`MySwiftUIVideoSDK/MySwiftUIVideoSDK.entitlements` — set to `development`; change to `production` for TestFlight/App Store)
- A **paid Apple Developer account** and a device to test VoIP pushes (they don't work in the Simulator). Set your team/bundle id and enable Push Notifications in Xcode's Signing & Capabilities.

## Need Help?
If you're looking for help, try Developer Support or our Developer Forums. Priority support is also available with Zoom Premier Developer Support plans.
