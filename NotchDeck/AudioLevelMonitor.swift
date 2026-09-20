import Foundation
import ScreenCaptureKit
import CoreMedia
import Combine

final class AudioLevelMonitor: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var level: Double = 0
    private(set) var isRunning = false

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "notchdeck.audio", qos: .userInteractive)
    private var smoothed: Double = 0
    private var peak: Double = 0.03
    private var lastPublish = Date.distantPast

    func start() {
        guard !isRunning, CGPreflightScreenCaptureAccess() else { return }
        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { self.isRunning = false; return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.capturesAudio = true
                cfg.excludesCurrentProcessAudio = true
                cfg.sampleRate = 48000
                cfg.channelCount = 2
                cfg.width = 8
                cfg.height = 8
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                cfg.showsCursor = false
                let s = SCStream(filter: filter, configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
                try await s.startCapture()
                self.stream = s
            } catch {
                self.isRunning = false
                SpacesManager.debugLog?("audio monitor failed: \(error)")
            }
        }
    }

    func stop() {
        isRunning = false
        guard let s = stream else { return }
        stream = nil
        Task { try? await s.stopCapture() }
        smoothed = 0
        DispatchQueue.main.async { self.level = 0 }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let block = sampleBuffer.dataBuffer else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == noErr,
              let p = ptr, length >= 4 else { return }
        let n = length / 4
        var sum: Float = 0
        p.withMemoryRebound(to: Float.self, capacity: n) { f in
            var i = 0
            while i < n { sum += f[i] * f[i]; i += 4 }
        }
        let rms = Double(sqrt(sum / Float(max(n / 4, 1))))
        peak = max(rms, peak * 0.998, 0.02)
        let norm = min(1, rms / peak)
        smoothed = norm > smoothed ? smoothed + (norm - smoothed) * 0.5 : smoothed + (norm - smoothed) * 0.12
        let now = Date()
        guard now.timeIntervalSince(lastPublish) > 1.0 / 30.0 else { return }
        lastPublish = now
        let v = smoothed
        DispatchQueue.main.async { self.level = v }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        self.stream = nil
        SpacesManager.debugLog?("audio monitor stopped: \(error)")
    }
}
