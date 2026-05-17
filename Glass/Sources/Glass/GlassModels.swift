import Foundation

enum CaptureSource: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            "You"
        case .systemAudio:
            "Meeting"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            "Mic channel"
        case .systemAudio:
            "System audio"
        }
    }

    var symbolName: String {
        switch self {
        case .microphone:
            "mic.fill"
        case .systemAudio:
            "waveform.badge.magnifyingglass"
        }
    }
}

struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
    let source: CaptureSource
    let text: String
    let date: Date

    var timeLabel: String {
        TranscriptSegment.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

struct ScreenInsight {
    let text: String
    let capturedAt: Date

    var headline: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No text found on the last screen scan." }
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        return firstLine.isEmpty ? "Screen scan captured." : firstLine
    }
}

struct CopilotAdvice {
    var summary: String
    var whatToSayNext: String
    var notes: [String]

    static let placeholder = CopilotAdvice(
        summary: "Start a live session and Glass will keep a rolling summary of the conversation.",
        whatToSayNext: "Glass will suggest short, natural replies here once it has some conversation context.",
        notes: [
            "System audio and microphone run in separate capture pipelines.",
            "Screen scans feed OCR text into the live copilot context."
        ]
    )
}

enum OpenAITextModel: String, CaseIterable, Identifiable {
    case gpt52 = "gpt-5.2"
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"
    case gpt41 = "gpt-4.1"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpt52:
            "GPT-5.2"
        case .gpt5Mini:
            "GPT-5 mini"
        case .gpt5Nano:
            "GPT-5 nano"
        case .gpt41:
            "GPT-4.1"
        case .gpt41Mini:
            "GPT-4.1 mini"
        case .gpt4o:
            "GPT-4o"
        case .gpt4oMini:
            "GPT-4o mini"
        }
    }

    var subtitle: String {
        switch self {
        case .gpt52:
            "Best overall reasoning quality"
        case .gpt5Mini:
            "Fast reasoning for live meetings"
        case .gpt5Nano:
            "Fastest and lightest GPT-5 option"
        case .gpt41:
            "Strong general text model"
        case .gpt41Mini:
            "Lower-latency GPT-4.1 variant"
        case .gpt4o:
            "Versatile multimodal flagship"
        case .gpt4oMini:
            "Budget-friendly live copilot model"
        }
    }

    var supportsReasoningEffort: Bool {
        switch self {
        case .gpt52, .gpt5Mini, .gpt5Nano:
            true
        case .gpt41, .gpt41Mini, .gpt4o, .gpt4oMini:
            false
        }
    }
}

enum OpenAIReasoningEffort: String, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high
    case extraHigh = "extra_high"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "None"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .extraHigh:
            "Extra High"
        }
    }

    var apiValue: String? {
        switch self {
        case .none:
            nil
        case .low:
            "low"
        case .medium:
            "medium"
        case .high:
            "high"
        case .extraHigh:
            "high"
        }
    }
}

enum GlassPreferences {
    private static let selectedTextModelKey = "glass.openai.textModel"
    private static let selectedReasoningEffortKey = "glass.openai.reasoningEffort"

    static func loadTextModel() -> OpenAITextModel {
        guard let stored = UserDefaults.standard.string(forKey: selectedTextModelKey),
              let model = OpenAITextModel(rawValue: stored) else {
            return .gpt5Mini
        }
        return model
    }

    static func saveTextModel(_ model: OpenAITextModel) {
        UserDefaults.standard.set(model.rawValue, forKey: selectedTextModelKey)
    }

    static func loadReasoningEffort() -> OpenAIReasoningEffort {
        guard let stored = UserDefaults.standard.string(forKey: selectedReasoningEffortKey),
              let effort = OpenAIReasoningEffort(rawValue: stored) else {
            return .medium
        }
        return effort
    }

    static func saveReasoningEffort(_ effort: OpenAIReasoningEffort) {
        UserDefaults.standard.set(effort.rawValue, forKey: selectedReasoningEffortKey)
    }
}

struct OpenAIServiceError: LocalizedError {
    let message: String
    let shouldTryNextModel: Bool

    var errorDescription: String? {
        message
    }
}
