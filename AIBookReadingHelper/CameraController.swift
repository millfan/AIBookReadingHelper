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
    private var rotatePendingCapture = false

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

    /// Takes a photo of the page. `rotated180` turns the photo upside down to match a rotated preview.
    func capturePage(rotated180: Bool) {
        guard status == .running else { return }
        errorMessage = nil
        rotatePendingCapture = rotated180
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
                self.capturedImage = self.rotatePendingCapture ? Self.rotated180(image) : image
            } else {
                self.errorMessage = message ?? "The photo could not be read."
            }
        }
    }
}

extension CameraController {
    /// Returns `image` turned upside down, so Live Text reads a page photographed with the camera rotated.
    static func rotated180(_ image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: cgImage.width,
                                      height: cgImage.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        context.translateBy(x: width, y: height)
        context.rotate(by: .pi)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rotated = context.makeImage() else { return image }
        return NSImage(cgImage: rotated, size: image.size)
    }
}
