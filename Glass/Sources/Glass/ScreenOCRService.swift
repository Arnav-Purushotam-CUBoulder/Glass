import Foundation
import CoreGraphics
import ScreenCaptureKit
import Vision

enum ScreenOCRService {
    static func captureCurrentDisplayText(displayID: CGDirectDisplayID? = nil) async throws -> ScreenInsight {
        let shareableContent = try await SCShareableContent.current
        let display = displayID.flatMap { id in
            shareableContent.displays.first(where: { $0.displayID == id })
        } ?? shareableContent.displays.first

        guard let display else {
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
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false

        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: OpenAIServiceError(message: "Screen capture returned no image.", shouldTryNextModel: false))
                }
            }
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let text = (request.results ?? [])
            .compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return ScreenInsight(
            text: text.isEmpty ? ScreenInsight.emptyTextMessage : text,
            capturedAt: Date()
        )
    }
}
