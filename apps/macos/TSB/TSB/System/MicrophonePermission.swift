import AVFoundation

enum MicrophonePermissionDecision: Equatable {
    case proceed
    case request
    case openSettings
}

struct MicrophoneRequestLatch {
    private var isInFlight = false

    mutating func begin() -> Bool {
        guard !isInFlight else { return false }
        isInFlight = true
        return true
    }

    mutating func finish() {
        isInFlight = false
    }
}

/// Adapted from the microphone-only branch of OpenDictation/Core/Services/PermissionsManager.swift (MIT, Copyright (c) 2025 Kenny).
@MainActor
enum MicrophonePermission {
    static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    nonisolated static func decision(for status: AVAuthorizationStatus) -> MicrophonePermissionDecision {
        switch status {
        case .authorized: .proceed
        case .notDetermined: .request
        case .denied, .restricted: .openSettings
        @unknown default: .openSettings
        }
    }

    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        Task { @MainActor in
            switch decision(for: AVCaptureDevice.authorizationStatus(for: .audio)) {
            case .proceed:
                completion(true)
            case .request:
                completion(await AVCaptureDevice.requestAccess(for: .audio))
            case .openSettings:
                completion(false)
            }
        }
    }
}
