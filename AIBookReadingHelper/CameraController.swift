import AVFoundation
import AppKit

/// Owns the capture session for the Mac's camera and turns a button press into a captured page image.
@MainActor
final class CameraController: NSObject, ObservableObject {
    enum Status {
        case idle
        case running
        case unauthorized
        case unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var capturedImage: NSImage?
    @Published private(set) var errorMessage: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "AIBookReadingHelper.camera")
    private var isConfigured = false

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .unauthorized
                return
            }
        default:
            status = .unauthorized
            return
        }

        if !isConfigured {
            guard configureSession() else {
                status = .unavailable
                return
            }
            isConfigured = true
        }

        let session = self.session
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
        status = .running
    }

    func stop() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func capturePage() {
        guard status == .running else { return }
        errorMessage = nil
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func retake() {
        capturedImage = nil
    }

    private func configureSession() -> Bool {
        // Prefer the built-in FaceTime camera, but fall back to any camera that is attached.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            return false
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        return true
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(NSImage.init(data:))
        let message = error?.localizedDescription
        Task { @MainActor in
            if let image {
                self.capturedImage = image
            } else {
                self.errorMessage = message ?? "The photo could not be read."
            }
        }
    }
}
