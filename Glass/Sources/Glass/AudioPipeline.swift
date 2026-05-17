@preconcurrency import AVFoundation
import CoreMedia
@preconcurrency import ScreenCaptureKit
import Foundation

final class PCMFormatConverter {
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    func convert(buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0,
              let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            return nil
        }

        let frameRatio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio + 32)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            return nil
        }

        let state = ConverterInputState(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if state.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            state.didProvideInput = true
            outStatus.pointee = .haveData
            return state.buffer
        }

        guard status != .error,
              conversionError == nil,
              let audioData = outputBuffer.audioBufferList.pointee.mBuffers.mData else {
            return nil
        }

        return Data(bytes: audioData, count: Int(outputBuffer.audioBufferList.pointee.mBuffers.mDataByteSize))
    }

    func convert(sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pcmBuffer = AudioSampleBufferBridge.makePCMBuffer(from: sampleBuffer) else {
            return nil
        }
        return convert(buffer: pcmBuffer)
    }
}

final class ConverterInputState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

enum AudioSampleBufferBridge {
    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: streamDescription) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )

        guard status == noErr else {
            return nil
        }

        return buffer
    }
}

final class MicrophoneCaptureService: @unchecked Sendable {
    var onPCMData: ((Data) -> Void)?

    private let engine = AVAudioEngine()
    private let converter = PCMFormatConverter()
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self,
                  let data = self.converter.convert(buffer: buffer),
                  !data.isEmpty else {
                return
            }
            self.onPCMData?(data)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}

enum SystemAudioCaptureError: LocalizedError {
    case screenPermissionRequired
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .screenPermissionRequired:
            "System audio capture needs Screen Recording permission."
        case .noDisplayAvailable:
            "No shareable display is available for system audio capture."
        }
    }
}

final class SystemAudioCaptureService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onPCMData: ((Data) -> Void)?
    var onError: ((Error) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?

    private let sampleQueue = DispatchQueue(label: "Glass.SystemAudioCapture")
    private let converter = PCMFormatConverter()
    private var stream: SCStream?
    private var isRunning = false

    func start() async throws {
        guard !isRunning else { return }
        guard CGPreflightScreenCaptureAccess() else {
            throw SystemAudioCaptureError.screenPermissionRequired
        }

        let shareableContent = try await SCShareableContent.current
        guard let display = shareableContent.displays.first else {
            throw SystemAudioCaptureError.noDisplayAvailable
        }

        let excludedApps = shareableContent.applications.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        self.stream = stream

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        isRunning = true
        onRunningChanged?(true)
    }

    func stop() {
        guard isRunning, let stream else { return }

        isRunning = false
        onRunningChanged?(false)
        self.stream = nil

        stream.stopCapture { [weak self] error in
            if let error {
                self?.onError?(error)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        onRunningChanged?(false)
        onError?(error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              let data = converter.convert(sampleBuffer: sampleBuffer),
              !data.isEmpty else {
            return
        }

        onPCMData?(data)
    }
}
