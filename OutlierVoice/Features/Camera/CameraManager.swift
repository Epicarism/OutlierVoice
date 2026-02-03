import AVFoundation
import SwiftUI
import UIKit

@Observable
@MainActor
class CameraManager: NSObject {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var lastCapturedImage: UIImage?
    var isAuthorized = false
    var isFrontCamera = true
    var isSessionReady = false  // Observable trigger for SwiftUI
    
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?
    
    override init() {
        super.init()
        Task { @MainActor in
            checkAuthorization()
        }
    }
    
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }
    
    private var isSettingUp = false
    
    func setupSession() {
        // Prevent double setup
        guard captureSession == nil && !isSettingUp else {
            print("[Camera] Session already exists or setting up, skipping")
            return
        }
        isSettingUp = true
        defer { isSettingUp = false }
        
        captureSession = AVCaptureSession()
        // Use low preset for smoothest preview - we only need visual, not capture quality
        captureSession?.sessionPreset = .low
        
        guard let session = captureSession else { return }
        
        // Get camera
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("[Camera] No camera available")
            return
        }
        currentDevice = device
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Photo output for snapshots
            let photo = AVCapturePhotoOutput()
            if session.canAddOutput(photo) {
                session.addOutput(photo)
                photoOutput = photo
            }
            
            // Video output for frame capture - only if we need snapshots
            // Disabled by default to reduce CPU usage and lag
            // Uncomment if you need lastCapturedImage for something
            /*
            let video = AVCaptureVideoDataOutput()
            video.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame"))
            video.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(video) {
                session.addOutput(video)
                videoOutput = video
            }
            */
            print("[Camera] Video output disabled for performance")
            
            print("[Camera] Session configured")
        } catch {
            print("[Camera] Setup error: \(error)")
        }
    }
    
    func startSession() {
        print("[Camera] startSession() called, captureSession: \(captureSession != nil), isAuthorized: \(isAuthorized)")
        
        // Setup if not already done
        if captureSession == nil && isAuthorized {
            print("[Camera] Session nil but authorized, setting up...")
            setupSession()
        }
        
        guard let session = captureSession else {
            print("[Camera] ERROR: No capture session!")
            return
        }
        
        guard !session.isRunning else {
            print("[Camera] Session already running")
            return
        }
        
        // Start on dedicated camera queue to avoid conflicts
        let cameraQueue = DispatchQueue(label: "camera.start", qos: .userInitiated)
        cameraQueue.async { [weak self] in
            session.startRunning()
            print("[Camera] Session started running")
            Task { @MainActor in
                self?.isSessionReady = true
                print("[Camera] isSessionReady = true")
            }
        }
    }
    
    func stopSession() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
            print("[Camera] Session stopped")
        }
    }
    
    func switchCamera() {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        
        // Remove current input
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        
        isFrontCamera.toggle()
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            currentDevice = device
        } catch {
            print("[Camera] Switch error: \(error)")
        }
        
        session.commitConfiguration()
    }
    
    /// Capture current frame as UIImage
    func captureSnapshot() -> UIImage? {
        return lastCapturedImage
    }
    
    /// Capture high-quality photo
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil)
            return
        }
        
        let settings = AVCapturePhotoSettings()
        let delegate = PhotoCaptureDelegate(completion: completion)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
        
        // Keep delegate alive
        objc_setAssociatedObject(photoOutput, "\(UUID())", delegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Video Frame Capture

// Non-isolated helper for frame processing
private enum FrameProcessor {
    // Shared CIContext - creating one per frame causes memory issues!
    static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Frame counter to skip frames (we don't need 30fps for snapshots)
    nonisolated(unsafe) static var frameCounter = 0
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only process every 30th frame (~1fps) to save memory
        FrameProcessor.frameCounter += 1
        guard FrameProcessor.frameCounter % 30 == 0 else { return }
        
        // Log occasionally
        if FrameProcessor.frameCounter % 90 == 0 {
            print("[Camera] Processing frame \(FrameProcessor.frameCounter)")
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        // Scale down for memory efficiency (640px wide)
        let scale = 640.0 / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = FrameProcessor.sharedCIContext.createCGImage(scaledImage, from: scaledImage.extent) else { return }
        
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        Task { @MainActor [weak self] in
            self?.lastCapturedImage = image
        }
    }
}

// MARK: - Photo Capture Delegate

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (UIImage?) -> Void
    
    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        DispatchQueue.main.async {
            self.completion(image)
        }
    }
}

// MARK: - SwiftUI Camera Preview

@MainActor
struct CameraPreviewView: UIViewRepresentable {
    @Bindable var cameraManager: CameraManager
    
    // This forces SwiftUI to call updateUIView when session becomes ready
    private var sessionTrigger: Bool { cameraManager.isSessionReady }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        context.coordinator.view = view
        
        print("[CameraPreview] makeUIView called, session: \(cameraManager.captureSession != nil), ready: \(cameraManager.isSessionReady)")
        
        if let session = cameraManager.captureSession {
            view.setupPreviewLayer(session: session)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        print("[CameraPreview] updateUIView called, session: \(cameraManager.captureSession != nil), ready: \(cameraManager.isSessionReady), layer: \(uiView.previewLayer != nil)")
        
        // Setup layer if session became available (wasn't ready in makeUIView)
        if uiView.previewLayer == nil, let session = cameraManager.captureSession {
            print("[CameraPreview] Setting up preview layer now (session became available)")
            uiView.setupPreviewLayer(session: session)
        }
        
        // Update frame in case bounds changed
        uiView.updateLayerFrame()
    }
    
    class Coordinator {
        weak var view: CameraPreviewUIView?
    }
}

/// Custom UIView that properly handles preview layer layout
class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    func setupPreviewLayer(session: AVCaptureSession) {
        print("[CameraPreview] setupPreviewLayer called, bounds: \(bounds)")
        
        // Remove existing layer if any
        previewLayer?.removeFromSuperlayer()
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        
        // Use a valid frame even if bounds are zero
        let frame = bounds.isEmpty ? CGRect(x: 0, y: 0, width: 300, height: 400) : bounds
        layer.frame = frame
        
        // Disable implicit animations for smoother updates
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer.addSublayer(layer)
        CATransaction.commit()
        
        previewLayer = layer
        print("[CameraPreview] Preview layer added, frame: \(frame)")
    }
    
    func updateLayerFrame() {
        guard let previewLayer = previewLayer, !bounds.isEmpty else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrame()
    }
}
