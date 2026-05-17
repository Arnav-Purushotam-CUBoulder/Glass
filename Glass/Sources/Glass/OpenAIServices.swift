import Foundation

final class OpenAIRealtimeTranscriber: @unchecked Sendable {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onReady: ((String) -> Void)?

    private let transcriptionModels = ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"]
    private let queue = DispatchQueue(label: "Glass.OpenAIRealtimeTranscriber")
    private let apiKey: String

    private var isRunning = false
    private var outboundAudio = Data()
    private var flushTimer: DispatchSourceTimer?
    private var isUploading = false
    private var shouldFlushAgain = false
    private let chunkByteThreshold = 24_000 * 2
    private let flushIntervalMs = 800

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func start() {
        queue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.startFlushTimer()
            self.onReady?(self.transcriptionModels[0])
        }
    }

    func stop() {
        queue.async {
            guard self.isRunning else { return }
            self.isRunning = false
            self.stopFlushTimer()
            self.flushBufferedAudio(force: true)
        }
    }

    func appendPCMData(_ data: Data) {
        queue.async {
            guard self.isRunning else { return }
            self.outboundAudio.append(data)
            if self.outboundAudio.count >= self.chunkByteThreshold {
                self.flushBufferedAudio(force: false)
            }
        }
    }

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(flushIntervalMs), repeating: .milliseconds(flushIntervalMs))
        timer.setEventHandler { [weak self] in
            self?.flushBufferedAudio(force: false)
        }
        timer.resume()
        flushTimer = timer
    }

    private func stopFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    private func flushBufferedAudio(force: Bool) {
        guard !outboundAudio.isEmpty else { return }
        if !force && outboundAudio.count < chunkByteThreshold / 2 {
            return
        }
        if isUploading {
            shouldFlushAgain = true
            return
        }

        let payload = outboundAudio
        outboundAudio.removeAll(keepingCapacity: true)
        isUploading = true

        let apiKey = self.apiKey
        let transcriptionModels = self.transcriptionModels
        Task.detached(priority: .userInitiated) { [weak self, apiKey, transcriptionModels, payload] in
            let result: Result<String, Error>
            do {
                let text = try await Self.transcribeChunk(
                    pcmData: payload,
                    apiKey: apiKey,
                    models: transcriptionModels
                )
                result = .success(text)
            } catch {
                result = .failure(error)
            }

            self?.queue.async {
                self?.handleFlushResult(result)
            }
        }
    }

    private func handleFlushResult(_ result: Result<String, Error>) {
        isUploading = false

        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onFinal?(trimmed)
            }
        case .failure(let error):
            onError?(error)
        }

        if shouldFlushAgain || (!outboundAudio.isEmpty && isRunning) {
            shouldFlushAgain = false
            flushBufferedAudio(force: false)
        }
    }

    private static func transcribeChunk(
        pcmData: Data,
        apiKey: String,
        models: [String]
    ) async throws -> String {
        guard !pcmData.isEmpty else { return "" }

        var lastError: Error?
        for model in models {
            do {
                return try await transcribeChunk(pcmData: pcmData, apiKey: apiKey, model: model)
            } catch let error as OpenAIServiceError {
                lastError = error
                if !error.shouldTryNextModel {
                    throw error
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? OpenAIServiceError(message: "OpenAI chunk transcription failed.", shouldTryNextModel: false)
    }

    private static func transcribeChunk(
        pcmData: Data,
        apiKey: String,
        model: String
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendField(name: "model", value: model, boundary: boundary, body: &body)
        appendField(name: "response_format", value: "json", boundary: boundary, body: &body)
        appendFileData(
            name: "file",
            filename: "glass-live.wav",
            contentType: "audio/wav",
            data: wavData(from: pcmData),
            boundary: boundary,
            body: &body
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            let message = decodeErrorMessage(from: data) ?? "OpenAI returned HTTP \(statusCode)."
            let lowercased = message.lowercased()
            let shouldTryNextModel = lowercased.contains("model") || lowercased.contains("not found") || lowercased.contains("unsupported")
            throw OpenAIServiceError(message: message, shouldTryNextModel: shouldTryNextModel)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIServiceError(message: "OpenAI returned an unreadable transcription response.", shouldTryNextModel: false)
        }

        return (json["text"] as? String) ?? ""
    }

    private static func wavData(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 24_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let riffSize = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: riffSize.littleEndianBytes)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: UInt32(16).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes)
        data.append(contentsOf: channels.littleEndianBytes)
        data.append(contentsOf: sampleRate.littleEndianBytes)
        data.append(contentsOf: byteRate.littleEndianBytes)
        data.append(contentsOf: blockAlign.littleEndianBytes)
        data.append(contentsOf: bitsPerSample.littleEndianBytes)
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: dataSize.littleEndianBytes)
        data.append(pcmData)
        return data
    }

    private static func appendField(name: String, value: String, boundary: String, body: inout Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private static func appendFileData(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String,
        body: inout Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    private static func decodeErrorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = json["message"] as? String {
            return message
        }

        return nil
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        return decodeErrorMessage(from: json)
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}

enum OpenAICopilotService {
    static func generateAdvice(
        transcriptSegments: [TranscriptSegment],
        partials: [CaptureSource: String],
        screenInsight: ScreenInsight?,
        apiKey: String,
        model: OpenAITextModel,
        reasoningEffort: OpenAIReasoningEffort,
        preferredCodeLanguage: CopilotCodeLanguage?
    ) async throws -> CopilotAdvice {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let transcriptContext = transcriptSegments.suffix(24).map { segment in
            "[\(segment.timeLabel)] \(segment.source.title): \(segment.text)"
        }.joined(separator: "\n")

        let partialContext = partials
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.title) (live): \($0.value)" }
            .joined(separator: "\n")

        let screenContext = screenInsight?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? screenInsight!.text
            : "No recent screen OCR."

        let preferredLanguageInstruction: String
        if let preferredCodeLanguage {
            preferredLanguageInstruction = "If code is needed, use exactly \(preferredCodeLanguage.sectionValue) for the CODE section."
        } else {
            preferredLanguageInstruction = "If code is needed, choose the most natural language for the task, but prefer concise natural-language guidance when full code is unnecessary."
        }

        let prompt = """
        You are Glass, a live meeting copilot.

        Use the rolling transcript and optional screen OCR to help the user in real time.
        Treat both audio channels as one shared meeting context:
        - Meeting = laptop/system audio coming from this Mac
        - You = microphone/room/outside audio near the user
        Keep the answer concise and practical.
        If transcript context is still sparse but screen OCR is useful, answer from the screen context instead of waiting.
        Identify any explicit or implied questions in the current context and answer them directly.
        If multiple questions appear, prioritize the newest active question first and then cover the rest briefly.
        If the current context shows a DSA, coding, algorithmic, interview, or implementation problem, do not stop at advice alone.
        For those problems, explain the approach lightly first, mention the key time and space complexity, and include a complete solution in the requested language.
        \(preferredLanguageInstruction)
        Put that solution in the CODE section as raw code only.
        For DSA or coding problems, every non-empty executable code line must have its own standalone comment line immediately above it.
        Do not let one comment cover multiple code lines.
        Use # comments for python and // comments for cpp.
        Do not wrap the code in markdown fences.
        If the current context is not a coding task, set CODE to None.

        Return exactly these sections:
        SUMMARY:
        one short paragraph

        WHAT TO SAY NEXT:
        one to three crisp lines the user can say naturally, or a brief direct answer if someone asked a question, or a brief plain-English explanation if this is a coding task

        NOTES:
        up to three bullet points with risks, follow-ups, or context shifts

        CODE_LANGUAGE:
        python, cpp, or none

        CODE:
        raw code only with no markdown fences, or None if code is not needed

        Transcript:
        \(transcriptContext)

        Live partials:
        \(partialContext.isEmpty ? "None" : partialContext)

        Screen OCR:
        \(screenContext)
        """

        var payload: [String: Any] = [
            "model": model.rawValue,
            "input": prompt
        ]

        if model.supportsReasoningEffort, let effort = reasoningEffort.apiValue {
            payload["reasoning"] = ["effort": effort]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            let message = decodeErrorMessage(from: data) ?? "OpenAI returned HTTP \(statusCode)."
            throw OpenAIServiceError(message: message, shouldTryNextModel: false)
        }

        guard let outputText = decodeOutputText(from: data),
              !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIServiceError(message: "OpenAI returned an empty copilot response.", shouldTryNextModel: false)
        }

        return parseAdvice(from: outputText)
    }

    private static func parseAdvice(from text: String) -> CopilotAdvice {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let summary = extractSection("SUMMARY", in: normalized)
        let sayNext = extractSection("WHAT TO SAY NEXT", in: normalized)
        let notesSection = extractSection("NOTES", in: normalized)
        let codeLanguageSection = extractSection("CODE_LANGUAGE", in: normalized)
        let codeSection = extractSection("CODE", in: normalized)

        let notes = notesSection
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                if line.hasPrefix("-") || line.hasPrefix("•") {
                    return String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return line
            }

        return CopilotAdvice(
            summary: summary.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : summary,
            whatToSayNext: sayNext.isEmpty ? "No suggested response yet." : sayNext,
            notes: notes.isEmpty ? ["No extra notes from the model."] : Array(notes.prefix(3)),
            codeLanguage: cleanCodeLanguageSection(codeLanguageSection),
            code: cleanCodeSection(codeSection)
        )
    }

    private static func extractSection(_ heading: String, in text: String) -> String {
        let markers = ["SUMMARY", "WHAT TO SAY NEXT", "NOTES", "CODE_LANGUAGE", "CODE"]
        guard let startRange = text.range(of: "\(heading):") else {
            return ""
        }

        let afterStart = text[startRange.upperBound...]
        let nextStart = markers
            .filter { $0 != heading }
            .compactMap { marker -> Range<String.Index>? in
                afterStart.range(of: "\n\(marker):")
            }
            .min(by: { $0.lowerBound < $1.lowerBound })

        let section = nextStart.map { afterStart[..<$0.lowerBound] } ?? afterStart[...]
        return section.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanCodeSection(_ codeSection: String) -> String? {
        let trimmed = codeSection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.caseInsensitiveCompare("none") != .orderedSame else { return nil }

        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3 else { return trimmed }
            return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func cleanCodeLanguageSection(_ codeLanguageSection: String) -> CopilotCodeLanguage? {
        let trimmed = codeLanguageSection.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != "none" else { return nil }

        if trimmed == "python" {
            return .python
        }

        if trimmed == "cpp" || trimmed == "c++" || trimmed == "cplusplus" {
            return .cpp
        }

        return nil
    }

    private static func decodeOutputText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let direct = json["output_text"] as? String,
           !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return direct
        }

        guard let output = json["output"] as? [[String: Any]] else {
            return nil
        }

        var chunks: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for contentItem in content {
                if let text = contentItem["text"] as? String {
                    chunks.append(text)
                } else if let nested = contentItem["output_text"] as? String {
                    chunks.append(nested)
                }
            }
        }

        let merged = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return merged.isEmpty ? nil : merged
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        return String(data: data, encoding: .utf8)
    }
}
