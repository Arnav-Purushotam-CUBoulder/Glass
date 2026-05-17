import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class GlassViewModel: ObservableObject {
    @Published var apiKey: String = GlassKeychain.loadOpenAIKey()
    @Published var statusText = "Ready for a live meeting"
    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var liveMicrophoneText = ""
    @Published var liveSystemText = ""
    @Published var copilotAdvice = CopilotAdvice.placeholder
    @Published var copilotHistory: [CopilotResponseEntry] = []
    @Published var latestScreenInsight: ScreenInsight?
    @Published var errorText: String?
    @Published var isMeetingActive = false
    @Published var sessionStartedAt: Date?
    @Published var isRefreshingCopilot = false
    @Published var isScanningScreen = false
    @Published var microphoneStatus = "Checking"
    @Published var systemAudioStatus = "Waiting"
    @Published var screenStatus = "Stealth On"
    @Published var screenAccessConfigured = false
    @Published var selectedTextModel: OpenAITextModel = GlassPreferences.loadTextModel()
    @Published var selectedReasoningEffort: OpenAIReasoningEffort = GlassPreferences.loadReasoningEffort()

    private let microphoneCapture = MicrophoneCaptureService()
    private let systemAudioCapture = SystemAudioCaptureService()

    private var microphoneTranscriber: OpenAIRealtimeTranscriber?
    private var systemAudioTranscriber: OpenAIRealtimeTranscriber?
    private var copilotRefreshTask: Task<Void, Never>?
    private var screenScanLoopTask: Task<Void, Never>?
    private var focusedDisplayID: CGDirectDisplayID?
    private var hasRequestedScreenAccessThisLaunch = false

    init() {
        microphoneCapture.onPCMData = { [weak self] data in
            self?.microphoneTranscriber?.appendPCMData(data)
        }

        systemAudioCapture.onPCMData = { [weak self] data in
            self?.systemAudioTranscriber?.appendPCMData(data)
        }

        systemAudioCapture.onRunningChanged = { [weak self] isRunning in
            Task { @MainActor [weak self] in
                self?.systemAudioStatus = isRunning ? "Live" : (self?.screenAccessConfigured == true ? "Ready" : "Needs Access")
            }
        }

        systemAudioCapture.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.systemAudioStatus = "Error"
                self?.errorText = self?.explainOpenAIError(error)
            }
        }
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var primaryButtonTitle: String {
        isMeetingActive ? "Stop Session" : "Start Session"
    }

    var modelLine: String {
        let effort = selectedTextModel.supportsReasoningEffort ? selectedReasoningEffort.title : "Standard"
        return "\(selectedTextModel.title) · Thinking \(effort)"
    }

    var hasCopilotContext: Bool {
        !transcriptSegments.isEmpty ||
        !liveMicrophoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !liveSystemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (latestScreenInsight?.hasRecognizedText == true)
    }

    func refreshPermissions() {
        microphoneStatus = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            "Allowed"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .notDetermined:
            "Not Asked"
        @unknown default:
            "Unknown"
        }

        screenAccessConfigured = CGPreflightScreenCaptureAccess()
        systemAudioStatus = isMeetingActive
            ? (screenAccessConfigured ? systemAudioStatus : "Mic Only")
            : (screenAccessConfigured ? "Ready" : "Needs Access")
        screenStatus = "Stealth On"
    }

    func requestScreenRecordingAccess() {
        screenAccessConfigured = CGPreflightScreenCaptureAccess()
        if screenAccessConfigured {
            errorText = nil
            statusText = "Screen access ready"
            refreshPermissions()
            return
        }

        hasRequestedScreenAccessThisLaunch = true
        let granted = CGRequestScreenCaptureAccess()
        screenAccessConfigured = granted || CGPreflightScreenCaptureAccess()
        refreshPermissions()

        if screenAccessConfigured {
            errorText = nil
            statusText = "Screen access granted"
            return
        }

        errorText = screenRecordingRestartHelpText
        statusText = "Relaunch required"

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    func saveSettings() -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try GlassKeychain.saveOpenAIKey(trimmed)
            persistModelPreferences()
            apiKey = GlassKeychain.loadOpenAIKey()

            if apiKey != trimmed {
                throw OpenAIServiceError(
                    message: "OpenAI settings could not be verified after saving. Please try again.",
                    shouldTryNextModel: false
                )
            }

            errorText = nil
            statusText = trimmed.isEmpty ? "OpenAI settings cleared" : "OpenAI settings saved"

            if isMeetingActive {
                restartTranscribersForUpdatedKey()
            }

            return true
        } catch {
            errorText = "Could not save API key: \(error.localizedDescription)"
            statusText = "Save failed"
            return false
        }
    }

    func saveModelPreferences(showStatus: Bool = false) {
        persistModelPreferences()
        if showStatus {
            statusText = "Model preferences saved"
        }
    }

    func selectTextModel(_ model: OpenAITextModel) {
        selectedTextModel = model
        saveModelPreferences(showStatus: true)
        if isMeetingActive, hasCopilotContext {
            scheduleCopilotRefresh()
        }
    }

    func selectReasoningEffort(_ effort: OpenAIReasoningEffort) {
        selectedReasoningEffort = effort
        saveModelPreferences(showStatus: true)
        if isMeetingActive, hasCopilotContext {
            scheduleCopilotRefresh()
        }
    }

    func relaunchApplication() {
        let appURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.errorText = "Could not relaunch Glass: \(error.localizedDescription)"
                    self?.statusText = "Relaunch failed"
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    func toggleMeeting() async {
        if isMeetingActive {
            stopMeeting()
        } else {
            await startMeeting()
        }
    }

    func setFocusedDisplayID(_ displayID: CGDirectDisplayID?) {
        focusedDisplayID = displayID
    }

    func analyzeCurrentScreen(promptForAccessIfNeeded: Bool = false) async {
        refreshPermissions()

        if !screenAccessConfigured, promptForAccessIfNeeded {
            requestScreenRecordingAccess()
            refreshPermissions()
        }

        await captureScreenContext(silent: false, refreshCopilot: false)

        guard errorText == nil else { return }

        if hasCopilotContext {
            await refreshCopilotNow()
        } else {
            statusText = "No screen text found yet"
        }
    }

    func refreshCopilotNow() async {
        guard hasAPIKey else {
            errorText = "Add an OpenAI API key to enable live transcription and live copilot replies."
            statusText = "Missing OpenAI key"
            return
        }

        if !hasCopilotContext {
            await captureScreenContext(silent: true, refreshCopilot: false)
        }

        guard hasCopilotContext else {
            statusText = screenAccessConfigured ? "Waiting for live context" : "Screen access needed"
            return
        }

        guard !isRefreshingCopilot else { return }
        isRefreshingCopilot = true
        errorText = nil
        statusText = "Updating copilot"

        do {
            let advice = try await OpenAICopilotService.generateAdvice(
                transcriptSegments: transcriptSegments,
                partials: [
                    .microphone: liveMicrophoneText,
                    .systemAudio: liveSystemText
                ],
                screenInsight: latestScreenInsight,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                model: selectedTextModel,
                reasoningEffort: selectedReasoningEffort
            )

            copilotAdvice = advice
            appendCopilotHistoryEntry(advice)
            statusText = "Copilot live"
        } catch {
            errorText = explainOpenAIError(error)
            statusText = "Copilot failed"
        }

        isRefreshingCopilot = false
    }

    func captureScreenContext(silent: Bool = false, refreshCopilot: Bool = true) async {
        guard !isScanningScreen else { return }

        isScanningScreen = true
        if !silent {
            statusText = "Scanning screen"
        }

        do {
            let insight = try await ScreenOCRService.captureCurrentDisplayText(displayID: focusedDisplayID)
            latestScreenInsight = insight
            errorText = nil
            screenAccessConfigured = true
            if !silent {
                statusText = "Screen context captured"
            }
            if refreshCopilot {
                scheduleCopilotRefresh()
            }
        } catch {
            let preflightAllowed = CGPreflightScreenCaptureAccess()
            screenAccessConfigured = preflightAllowed
            if preflightAllowed {
                if !silent {
                    statusText = "Screen scan failed"
                }
                errorText = explainOpenAIError(error)
            } else {
                errorText = hasRequestedScreenAccessThisLaunch
                    ? screenRecordingRestartHelpText
                    : screenRecordingHelpText
                statusText = hasRequestedScreenAccessThisLaunch
                    ? "Relaunch required"
                    : "Screen access needed"
            }
        }

        isScanningScreen = false
    }

    func stopImmediatelyForQuit() {
        copilotRefreshTask?.cancel()
        screenScanLoopTask?.cancel()
        microphoneCapture.stop()
        systemAudioCapture.stop()
        microphoneTranscriber?.stop()
        systemAudioTranscriber?.stop()
        microphoneTranscriber = nil
        systemAudioTranscriber = nil
        isMeetingActive = false
        sessionStartedAt = nil
        liveMicrophoneText = ""
        liveSystemText = ""
    }

    private func startMeeting() async {
        guard hasAPIKey else {
            errorText = "Add one OpenAI API key in Settings. Glass uses it for both live transcription and model replies."
            statusText = "Missing OpenAI key"
            return
        }

        let micAllowed = await requestMicrophoneAccessIfNeeded()
        refreshPermissions()

        guard micAllowed else {
            statusText = "Microphone access denied"
            errorText = "Enable Microphone access for Glass in System Settings > Privacy & Security > Microphone."
            return
        }

        transcriptSegments.removeAll()
        liveMicrophoneText = ""
        liveSystemText = ""
        copilotHistory.removeAll()
        latestScreenInsight = nil
        copilotAdvice = CopilotAdvice.placeholder
        errorText = nil
        isMeetingActive = true
        sessionStartedAt = Date()
        microphoneStatus = "Starting"
        systemAudioStatus = screenAccessConfigured ? "Starting" : "Mic Only"
        statusText = "Starting live capture"

        configureRealtimePipelines()

        do {
            try microphoneCapture.start()
            microphoneStatus = "Live"
        } catch {
            isMeetingActive = false
            sessionStartedAt = nil
            microphoneStatus = "Error"
            errorText = error.localizedDescription
            statusText = "Microphone failed"
            return
        }

        if screenAccessConfigured {
            do {
                try await systemAudioCapture.start()
                systemAudioStatus = "Live"
            } catch {
                systemAudioStatus = "Mic Only"
                errorText = explainOpenAIError(error)
            }
        }

        if screenAccessConfigured {
            statusText = "Scanning screen and listening live"
            await captureScreenContext(silent: true, refreshCopilot: false)
        } else {
            statusText = "Listening live"
        }

        startAutomaticScreenScanLoop()

        if hasCopilotContext {
            await refreshCopilotNow()
        } else {
            statusText = "Listening live"
        }
    }

    private func stopMeeting() {
        stopImmediatelyForQuit()
        refreshPermissions()
        statusText = "Session stopped"
    }

    private func configureRealtimePipelines() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let micTranscriber = OpenAIRealtimeTranscriber(apiKey: trimmedKey)
        micTranscriber.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.liveMicrophoneText = text
            }
        }
        micTranscriber.onFinal = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.appendFinalTranscript(text, from: .microphone)
            }
        }
        micTranscriber.onReady = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.microphoneStatus = "Live"
            }
        }
        micTranscriber.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.microphoneStatus = "Error"
                self?.errorText = self?.explainOpenAIError(error)
            }
        }
        micTranscriber.start()
        self.microphoneTranscriber = micTranscriber

        guard screenAccessConfigured else {
            systemAudioTranscriber?.stop()
            systemAudioTranscriber = nil
            return
        }

        let systemTranscriber = OpenAIRealtimeTranscriber(apiKey: trimmedKey)
        systemTranscriber.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.liveSystemText = text
            }
        }
        systemTranscriber.onFinal = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.appendFinalTranscript(text, from: .systemAudio)
            }
        }
        systemTranscriber.onReady = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.systemAudioStatus = "Live"
            }
        }
        systemTranscriber.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.systemAudioStatus = "Error"
                self?.errorText = self?.explainOpenAIError(error)
            }
        }
        systemTranscriber.start()
        self.systemAudioTranscriber = systemTranscriber
    }

    private func restartTranscribersForUpdatedKey() {
        microphoneTranscriber?.stop()
        systemAudioTranscriber?.stop()
        configureRealtimePipelines()
    }

    private func appendFinalTranscript(_ rawText: String, from source: CaptureSource) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch source {
        case .microphone:
            liveMicrophoneText = ""
        case .systemAudio:
            liveSystemText = ""
        }

        if let last = transcriptSegments.last, last.source == source, last.text == trimmed {
            return
        }

        transcriptSegments.append(
            TranscriptSegment(source: source, text: trimmed, date: Date())
        )

        if transcriptSegments.count > 80 {
            transcriptSegments.removeFirst(transcriptSegments.count - 80)
        }

        scheduleCopilotRefresh()
    }

    private func scheduleCopilotRefresh() {
        copilotRefreshTask?.cancel()
        copilotRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshCopilotNow()
        }
    }

    private func startAutomaticScreenScanLoop() {
        screenScanLoopTask?.cancel()
        guard screenAccessConfigured else { return }

        screenScanLoopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled, self.isMeetingActive else { break }
                await self.captureScreenContext(silent: true)
            }
        }
    }

    private func persistModelPreferences() {
        GlassPreferences.saveTextModel(selectedTextModel)
        GlassPreferences.saveReasoningEffort(selectedReasoningEffort)
    }

    private var screenRecordingHelpText: String {
        "Enable Screen Recording access so Glass can OCR slides and shared screens from the Settings button. After you grant it in macOS, quit and relaunch Glass once."
    }

    private var screenRecordingRestartHelpText: String {
        "Glass already asked macOS for screen access in this session. After turning the permission on, quit and relaunch Glass once so the grant can take effect."
    }

    private func appendCopilotHistoryEntry(_ advice: CopilotAdvice) {
        guard copilotHistory.last?.advice != advice else { return }

        copilotHistory.append(
            CopilotResponseEntry(
                advice: advice,
                createdAt: Date()
            )
        )

        if copilotHistory.count > 60 {
            copilotHistory.removeFirst(copilotHistory.count - 60)
        }
    }

    private func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    fileprivate func explainOpenAIError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lowercased = message.lowercased()

        if lowercased.contains("quota") || lowercased.contains("billing") {
            return "The OpenAI key is saved, but OpenAI rejected usage for quota or billing reasons on this project."
        }

        return message
    }
}
