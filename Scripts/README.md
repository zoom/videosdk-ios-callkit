# JWT Generator Script

This script generates Zoom Video SDK JWT tokens from the command line using swift. Please make sure you have swift installed and you can test it out using "swift --version" in your terminal.

## Usage

You can choose to either add the information needed to create the JWT tokens using .env file or through arguments.

### Comment-line with .env variables

In the .env file, ensure that these 4 variables are filled up.

```bash
SESSION_NAME=
ROLE=
SDK_KEY=
SDK_SECRET=
```

To generate JWT Token:

```bash
swift Scripts/JWTGenerator.swift
```

### Command-line with arguments

```bash
swift Scripts/JWTGenerator.swift <sessionName> <role> <sdkKey> <sdkSecret>
```

**Example:**

```bash
swift Scripts/JWTGenerator.swift TestSession12345 1 YourSDKKey YourSDKSecret
```

## Output

The script prints the JWT token to stdout (one line). You can copy it directly and add it under the JWT token field in the sample app project.

## Troubleshooting

If you get permission errors or your terminal just hangs, make sure the script is executable:

```bash
chmod +x Scripts/JWTGenerator.swift
```

---

# VoIP Push Sender (CallKit incoming-call testing)

`VoIPPush.swift` fires an APNs VoIP push at your device so the app rings a native
incoming call. This is a local stand-in for a real backend — use it to test the
CallKit incoming flow end to end.

**Requires a paid Apple Developer account** (VoIP pushes need an APNs auth key and a
provisioning profile with Push Notifications + the VoIP background mode).

## One-time setup

1. Apple Developer portal → **Certificates, Identifiers & Profiles → Keys** → create a key
   with **Apple Push Notifications service (APNs)** enabled. Download the `.p8` (once only).
   Note its **Key ID** and your **Team ID**.
2. Get the app's **VoIP device token**: run the app on a real device and copy the
   `VoIP device token: ...` line from the Xcode console (logged in `AppDelegate`).
3. Fill in `Scripts/.env` (or export as env vars):

   ```bash
   AUTH_KEY_PATH=/absolute/path/to/AuthKey_XXXX.p8
   KEY_ID=XXXXXXXXXX
   TEAM_ID=YYYYYYYYYY
   BUNDLE_ID=com.your.bundleid       # the app's bundle id; topic sent is <BUNDLE_ID>.voip
   APNS_ENV=sandbox                  # sandbox for dev builds; prod for TestFlight/App Store
   ```

## Usage

```bash
swift Scripts/VoIPPush.swift <deviceToken> <sessionName> <vsdkJWT> [callerName]
```

`<vsdkJWT>` is a Video SDK session token for `<sessionName>` — generate it with
`JWTGenerator.swift` above. Example:

```bash
swift Scripts/VoIPPush.swift 6a1f...c9 TestSession12345 eyJ0eXAi... "Alice"
```

On success it prints `Sent (200)` and the device shows the native incoming-call UI.
Answering joins the Video SDK session with that token.

