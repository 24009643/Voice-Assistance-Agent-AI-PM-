import AVFoundation

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

    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        Task { @MainActor in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                completion(true)
            case .notDetermined:
                completion(await AVCaptureDevice.requestAccess(for: .audio))
            case .denied, .restricted:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }
}
