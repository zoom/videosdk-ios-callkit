#!/usr/bin/env swift
// Sends a CallKit VoIP push to a device via APNs, so the app rings an incoming call.
// ponytail: local test tool — a real backend replaces this. No deps beyond macOS CryptoKit.
//
// Usage (args or env vars, args win):
//   swift Scripts/VoIPPush.swift <deviceToken> <sessionName> <vsdkJWT> [callerName]
// Auth + target come from env / .env: AUTH_KEY_PATH, KEY_ID, TEAM_ID, BUNDLE_ID, APNS_ENV.

import Foundation
import CryptoKit

// MARK: - Config (env / .env, then positional args)

func loadDotEnv() {
    let path = FileManager.default.currentDirectoryPath + "/Scripts/.env"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        if ProcessInfo.processInfo.environment[key] == nil {
            setenv(key, parts[1].trimmingCharacters(in: .whitespaces), 1)
        }
    }
}
loadDotEnv()

func env(_ k: String) -> String? { ProcessInfo.processInfo.environment[k] }
let args = Array(CommandLine.arguments.dropFirst())

func require(_ v: String?, _ name: String) -> String {
    guard let v, !v.isEmpty else {
        FileHandle.standardError.write("Missing \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    return v
}

let authKeyPath = require(env("AUTH_KEY_PATH"), "AUTH_KEY_PATH (.p8 file)")
let keyID       = require(env("KEY_ID"), "KEY_ID")
let teamID      = require(env("TEAM_ID"), "TEAM_ID")
let bundleID    = require(env("BUNDLE_ID"), "BUNDLE_ID")
let apnsEnv     = env("APNS_ENV") ?? "sandbox" // "sandbox" for dev builds, "prod" for TestFlight/App Store

let deviceToken = require(args.count > 0 ? args[0] : nil, "deviceToken (arg 1)")
let sessionName = require(args.count > 1 ? args[1] : nil, "sessionName (arg 2)")
let vsdkJWT     = require(args.count > 2 ? args[2] : nil, "vsdkJWT (arg 3)")
let callerName  = args.count > 3 ? args[3] : "Incoming Call"

// MARK: - ES256 provider JWT

func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func providerToken() -> String {
    guard let pem = try? String(contentsOfFile: authKeyPath, encoding: .utf8),
          let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
        FileHandle.standardError.write("Could not read/parse .p8 at \(authKeyPath)\n".data(using: .utf8)!)
        exit(1)
    }
    let header = #"{"alg":"ES256","kid":"\#(keyID)"}"#
    let iat = Int(Date().timeIntervalSince1970)
    let payload = #"{"iss":"\#(teamID)","iat":\#(iat)}"#
    let signingInput = base64url(Data(header.utf8)) + "." + base64url(Data(payload.utf8))
    let sig = try! key.signature(for: Data(signingInput.utf8))
    return signingInput + "." + base64url(sig.rawRepresentation)
}

// MARK: - Send

let host = apnsEnv == "prod" ? "api.push.apple.com" : "api.sandbox.push.apple.com"
var req = URLRequest(url: URL(string: "https://\(host)/3/device/\(deviceToken)")!)
req.httpMethod = "POST"
req.setValue("bearer \(providerToken())", forHTTPHeaderField: "authorization")
req.setValue("\(bundleID).voip", forHTTPHeaderField: "apns-topic")
req.setValue("voip", forHTTPHeaderField: "apns-push-type")
req.setValue("10", forHTTPHeaderField: "apns-priority")

// Payload the app's AppDelegate reads. ponytail: JWT sent inline for testing; fetch it
// server-side on answer in production.
let body: [String: Any] = [
    "sessionName": sessionName,
    "token": vsdkJWT,
    "userName": env("USER_NAME") ?? "Me",
    "callerName": callerName,
]
req.httpBody = try! JSONSerialization.data(withJSONObject: body)

let sem = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: req) { data, response, error in
    defer { sem.signal() }
    if let error { print("Error: \(error)"); return }
    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
    let reason = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    print(code == 200 ? "Sent (200)" : "APNs \(code): \(reason)")
}.resume()
sem.wait()
