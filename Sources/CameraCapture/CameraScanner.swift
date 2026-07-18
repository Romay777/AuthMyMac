@preconcurrency import AVFoundation
import Foundation
import ImageIO
import QR

/// QR-only camera scanner. Its capture session ends after the first valid payload.
public final class CameraScanner: NSObject, @unchecked Sendable, CameraScanning, AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let frameSamplingInterval = 10

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "dev.geeky.authmymac.camera-scanner")
    private let lock = NSLock()
    private let frameDetector = CameraFrameQRDetector()
    private var state: ScanState = .idle
    private var frameNumber = 0
    private var scannedValueDecoder: CameraScannedValueDecoder
    private var migrationProgressHandler: (@Sendable (MigrationScanProgress) -> Void)?

    public var captureSession: AVCaptureSession { session }

    public init(decoder: any QRPayloadDecoding = QRPayloadDecoder()) {
        self.scannedValueDecoder = CameraScannedValueDecoder(decoder: decoder)
        super.init()
    }

    public func authorizationState() async -> CameraAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .unavailable
        }
    }

    public func scan() async throws -> QRPayload {
        try await scan(onMigrationProgress: { _ in })
    }

    public func scan(
        onMigrationProgress: @escaping @Sendable (MigrationScanProgress) -> Void
    ) async throws -> QRPayload {
        try Task.checkCancellation()
        let token = try beginScan(onMigrationProgress: onMigrationProgress)

        return try await withTaskCancellationHandler(operation: {
            do {
                if await authorizationState() == .notDetermined {
                    guard await AVCaptureDevice.requestAccess(for: .video) else {
                        throw CameraScanError.permissionDenied
                    }
                }
                guard await authorizationState() == .authorized else {
                    throw CameraScanError.permissionDenied
                }
                return try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    switch state {
                    case let .preparing(currentToken) where currentToken == token:
                        state = .waiting(token, continuation)
                        lock.unlock()
                        queue.async { [weak self] in self?.startSession(for: token) }
                    case let .cancelled(currentToken) where currentToken == token:
                        state = .idle
                        lock.unlock()
                        continuation.resume(throwing: CameraScanError.cancelled)
                    default:
                        lock.unlock()
                        continuation.resume(throwing: CameraScanError.cancelled)
                    }
                }
            } catch {
                clearState(for: token)
                throw error
            }
        }, onCancel: { [weak self] in
            self?.cancel(token: token)
        })
    }

    public func stop() async {
        cancel()
        await waitForSessionToStop()
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let token = waitingToken(),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        frameNumber = (frameNumber + 1) % Self.frameSamplingInterval
        guard frameNumber == 0 else { return }

        do {
            let values = try frameDetector.detectValues(
                in: imageBuffer,
                orientation: imageOrientation(for: connection)
            )
            for value in values {
                guard isWaiting(for: token) else { return }
                handleScannedValue(value, for: token)
            }
        } catch {
            return
        }
    }

    private func startSession(for token: UUID) {
        guard isWaiting(for: token) else { return }
        do {
            try configureSessionIfNeeded()
            guard isWaiting(for: token) else { return }
            if !session.isRunning { session.startRunning() }
        } catch {
            finish(.failure(error), for: token)
        }
    }

    /// Must run on `queue`; AVFoundation requires configuration and running-state
    /// changes to be serialized.
    private func configureSessionIfNeeded() throws {
        guard !session.isRunning, session.inputs.isEmpty, session.outputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraScanError.noDevice
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraScanError.noDevice
        }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CameraScanError.noDevice
        }

        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        configureCamera(device)

        // Keep the buffer orientation stable for Vision and the preview. The
        // handler still reads the connection in case a capture device changes it.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
    }

    private func configureCamera(_ device: AVCaptureDevice) {
        guard device.isFocusModeSupported(.continuousAutoFocus)
                || device.isExposureModeSupported(.continuousAutoExposure)
        else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
        } catch {
            // Focus/exposure are device capabilities, not scan prerequisites.
        }
    }

    private func imageOrientation(for connection: AVCaptureConnection) -> CGImagePropertyOrientation {
        let angle = Int(connection.videoRotationAngle.rounded()) % 360
        return switch (angle, connection.isVideoMirrored) {
        case (90, false): CGImagePropertyOrientation.right
        case (180, false): CGImagePropertyOrientation.down
        case (270, false): CGImagePropertyOrientation.left
        case (90, true): CGImagePropertyOrientation.leftMirrored
        case (180, true): CGImagePropertyOrientation.downMirrored
        case (270, true): CGImagePropertyOrientation.rightMirrored
        case (_, true): CGImagePropertyOrientation.upMirrored
        default: CGImagePropertyOrientation.up
        }
    }

    private func waitingToken() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        if case let .waiting(token, _) = state { return token }
        return nil
    }

    private func isWaiting(for token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case let .waiting(currentToken, _) = state {
            return currentToken == token
        }
        return false
    }

    private func handleScannedValue(_ value: String, for token: UUID) {
        guard isWaiting(for: token) else { return }
        do {
            if let payload = try scannedValueDecoder.decode(value) {
                finish(.success(payload), for: token)
            } else if let progress = scannedValueDecoder.takeMigrationProgress() {
                migrationProgressHandler?(progress)
            }
        } catch {
            finish(.failure(error), for: token)
        }
    }

    private func finish(_ result: Result<QRPayload, Error>, for token: UUID) {
        lock.lock()
        let continuation: CheckedContinuation<QRPayload, Error>?
        if case let .waiting(currentToken, waitingContinuation) = state,
           currentToken == token {
            continuation = waitingContinuation
            state = .idle
        } else {
            continuation = nil
        }
        lock.unlock()
        guard let continuation else { return }
        queue.async { [weak self] in
            self?.stopAndTearDownSession()
        }
        continuation.resume(with: result)
    }

    private func beginScan(
        onMigrationProgress: @escaping @Sendable (MigrationScanProgress) -> Void
    ) throws -> UUID {
        lock.lock()
        defer { lock.unlock() }
        guard case .idle = state else { throw CameraScanError.cancelled }
        let token = UUID()
        state = .preparing(token)
        queue.async { [weak self] in
            self?.frameNumber = 0
            self?.scannedValueDecoder.reset()
            self?.migrationProgressHandler = onMigrationProgress
        }
        return token
    }

    private func clearState(for token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case let .preparing(currentToken) where currentToken == token:
            state = .idle
        case let .cancelled(currentToken) where currentToken == token:
            state = .idle
        default:
            break
        }
        queue.async { [weak self] in
            self?.stopAndTearDownSession()
        }
    }

    private func cancel(token: UUID? = nil) {
        lock.lock()
        let continuation: CheckedContinuation<QRPayload, Error>?
        switch state {
        case .idle:
            continuation = nil
        case let .preparing(currentToken):
            guard token == nil || token == currentToken else {
                lock.unlock()
                return
            }
            state = .cancelled(currentToken)
            continuation = nil
        case let .waiting(currentToken, waitingContinuation):
            guard token == nil || token == currentToken else {
                lock.unlock()
                return
            }
            state = .idle
            continuation = waitingContinuation
        case let .cancelled(currentToken):
            guard token == nil || token == currentToken else {
                lock.unlock()
                return
            }
            continuation = nil
        }
        lock.unlock()
        queue.async { [weak self] in
            self?.stopAndTearDownSession()
        }
        continuation?.resume(throwing: CameraScanError.cancelled)
    }

    /// Must run on `queue` after the session is stopped. Rebuilding the graph
    /// avoids restarting an AVFoundation session while it retains stale capture
    /// connections from an earlier presentation.
    private func stopAndTearDownSession() {
        migrationProgressHandler = nil
        if session.isRunning { session.stopRunning() }
        guard !session.inputs.isEmpty || !session.outputs.isEmpty else { return }

        session.beginConfiguration()
        output.setSampleBufferDelegate(nil, queue: nil)
        while let output = session.outputs.first {
            session.removeOutput(output)
        }
        while let input = session.inputs.first {
            session.removeInput(input)
        }
        session.commitConfiguration()
    }

    /// `cancel` is synchronous so it can run from a task cancellation handler.
    /// Callers that intend to start another scan await this barrier, which runs
    /// after every queued teardown operation for this session.
    private func waitForSessionToStop() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.stopAndTearDownSession()
                continuation.resume()
            }
        }
    }
}

struct CameraScannedValueDecoder {
    private let decoder: any QRPayloadDecoding
    private var migrationReassembler = MigrationPayloadReassembler()
    private var migrationProgress: MigrationScanProgress?
    private var lastReportedProgress: MigrationScanProgress?

    init(decoder: any QRPayloadDecoding = QRPayloadDecoder()) {
        self.decoder = decoder
    }

    mutating func decode(_ value: String) throws -> QRPayload? {
        do {
            if let migrationDecoder = decoder as? any MigrationBatchDecoding,
               let batch = try migrationDecoder.decodeMigrationBatch(value) {
                guard let accounts = try migrationReassembler.append(batch) else {
                    let progress = MigrationScanProgress(
                        scannedCount: migrationReassembler.receivedBatchCount,
                        totalCount: batch.batchSize
                    )
                    if progress != lastReportedProgress {
                        migrationProgress = progress
                        lastReportedProgress = progress
                    }
                    return nil
                }
                return .migration(accounts)
            }
            return try decoder.decode(value)
        } catch {
            throw CameraScanError.invalidPayload
        }
    }

    mutating func reset() {
        migrationReassembler.reset()
        migrationProgress = nil
        lastReportedProgress = nil
    }

    mutating func takeMigrationProgress() -> MigrationScanProgress? {
        defer { migrationProgress = nil }
        return migrationProgress
    }
}

private enum ScanState {
    case idle
    case preparing(UUID)
    case waiting(UUID, CheckedContinuation<QRPayload, Error>)
    case cancelled(UUID)
}
