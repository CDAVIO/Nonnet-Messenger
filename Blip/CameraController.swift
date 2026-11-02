import AVFoundation
import SwiftUI

/// Photos and silent video (no microphone). Front camera by default, 640x480 capture.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var position: AVCaptureDevice.Position = .front
    @Published private(set) var recordStart: Date?

    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoDone: ((Data?) -> Void)?
    private var videoInput: AVCaptureDeviceInput?
    private let queue = DispatchQueue(label: "blip.camera")
    private var configured = false
    private var movieDone: ((URL?) -> Void)?

    var isRecording: Bool { recordStart != nil }
    var hasBackCamera: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

    func start() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else { return }
            queue.async {
                self.configure()
                self.session.startRunning()
            }
        }
    }

    func stop() {
        setTorch(false)
        queue.async { self.session.stopRunning() }
    }

    func switchCamera() {
        setTorch(false)
        queue.async {
            let next: AVCaptureDevice.Position = self.position == .front ? .back : .front
            self.session.beginConfiguration()
            let switched = self.setVideoInput(next)
            self.session.commitConfiguration()
            guard switched else { return }
            self.applyOrientation(next)
            DispatchQueue.main.async { self.position = next }
        }
    }

    /// Records up to 10 s × speed of real time, so the sped-up result is always ≤ 10 s.
    func startRecording(speed: Double, done: @escaping (URL?) -> Void) {
        guard !isRecording else { return }
        movieDone = done
        movieOutput.maxRecordedDuration = CMTime(seconds: MediaProcessor.maxVideoSeconds * speed, preferredTimescale: 600)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        recordStart = Date()
        queue.async { self.movieOutput.startRecording(to: url, recordingDelegate: self) }
    }

    /// Calls back with nil if the camera isn't running yet (or access was denied) instead of crashing.
    func takePhoto(done: @escaping (Data?) -> Void) {
        guard photoDone == nil else { return }
        photoDone = done
        queue.async {
            guard self.session.isRunning, self.photoOutput.connection(with: .video)?.isEnabled == true else {
                DispatchQueue.main.async {
                    self.photoDone?(nil)
                    self.photoDone = nil
                }
                return
            }
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func stopRecording() {
        queue.async { self.movieOutput.stopRecording() }
    }

    /// The LED flash, back camera only. The front camera uses the white ring light on screen instead.
    func setTorch(_ on: Bool) {
        guard let device = videoInput?.device, device.hasTorch,
              (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: Setup

    private func configure() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        setVideoInput(.front)
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        applyOrientation(.front)
    }

    @discardableResult
    private func setVideoInput(_ position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? (position == .front ? AVCaptureDevice.default(for: .video) : nil),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        if let old = videoInput { session.removeInput(old) }
        guard session.canAddInput(input) else {
            if let old = videoInput { session.addInput(old) }
            return false
        }
        session.addInput(input)
        videoInput = input
        return true
    }

    private func applyOrientation(_ position: AVCaptureDevice.Position) {
        for output in [movieOutput, photoOutput] as [AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if !ProcessInfo.processInfo.isiOSAppOnMac, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            self.photoDone?(data)
            self.photoDone = nil
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Hitting the max duration reports an "error" even though the file is fine.
        let finished = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        DispatchQueue.main.async {
            self.recordStart = nil
            self.movieDone?(finished ? url : nil)
            self.movieDone = nil
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
