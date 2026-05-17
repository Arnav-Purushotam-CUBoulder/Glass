import AppKit
import SwiftUI

struct GlassRootView: View {
    @ObservedObject var model: GlassViewModel
    @State private var isShowingSettings = false
    @State private var isTranscriptVisible = false
    @State private var isShowingModelPicker = false

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 34
            let availableWidth = max(560, proxy.size.width - (horizontalPadding * 2))
            let panelWidth = min(920, max(560, availableWidth - 60))
            let controlBarWidth = min(760, max(420, panelWidth * 0.82))

            ZStack(alignment: .top) {
                overlayGlowLayer

                VStack(spacing: 24) {
                    floatingControlBar(width: controlBarWidth)
                    .padding(.top, 18)
                    .frame(maxWidth: .infinity, alignment: .center)

                    aiResponsePanel(width: panelWidth)
                    .padding(.horizontal, horizontalPadding)

                    Spacer(minLength: 24)
                }

                if isShowingSettings {
                    inlineSettingsOverlay
                }
            }
        }
    }

    private var overlayGlowLayer: some View {
        ZStack {
            Color.clear

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 340, height: 340)
                .blur(radius: 110)
                .offset(x: -340, y: 60)

            Circle()
                .fill(Color.orange.opacity(0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: 320, y: -150)

            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .offset(x: 420, y: 180)
        }
    }

    private func floatingControlBar(width: CGFloat) -> some View {
        HStack(spacing: 18) {
            Button {
                Task {
                    await model.toggleMeeting()
                }
            } label: {
                Image(systemName: model.isMeetingActive ? "pause.fill" : "record.circle.fill")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(.black.opacity(0.84))
                    .frame(width: 46, height: 46)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                AudioGlyph()
                SessionElapsedText(startDate: model.sessionStartedAt)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Spacer(minLength: 10)

            ControlBarAction(
                title: "Ask AI",
                keyHints: ["⌃", "⌥", "⌘", "R"]
            ) {
                Task {
                    await model.refreshCopilotNow()
                }
            }

            ControlBarAction(
                title: isTranscriptVisible ? "Hide transcript" : "Show transcript",
                keyHints: []
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    isTranscriptVisible.toggle()
                }
            }

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: width)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.64))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.13),
                                    Color.clear,
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .shadow(color: .black.opacity(0.34), radius: 28, y: 18)
    }

    private func aiResponsePanel(width: CGFloat) -> some View {
        DarkGlassPanel(width: width) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    Text("AI response")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    searchPromptPill

                    Spacer()

                    Button {
                        Task {
                            await model.analyzeCurrentScreen()
                        }
                    } label: {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isTranscriptVisible.toggle()
                        }
                    } label: {
                        Image(systemName: isTranscriptVisible ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .buttonStyle(.plain)
                }

                DividerLine()

                CopilotHistoryView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if let latestScreenInsight = model.latestScreenInsight,
                   latestScreenInsight.hasRecognizedText {
                    DividerLine()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Screen context")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(latestScreenInsight.headline)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                }

                if isTranscriptVisible {
                    DividerLine()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Transcript")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.94))
                            Spacer()
                            Text("Dual channel")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.48))
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if model.transcriptSegments.isEmpty && model.liveMicrophoneText.isEmpty && model.liveSystemText.isEmpty {
                                    TranscriptPlaceholderView(
                                        title: "Nothing live yet",
                                        subtitle: "Start a session and Glass will drop meeting and mic lines here."
                                    )
                                }

                                ForEach(model.transcriptSegments.suffix(8)) { segment in
                                    TranscriptBubble(segment: segment)
                                }

                                if !model.liveSystemText.isEmpty {
                                    LiveDraftBubble(
                                        title: "Meeting live",
                                        text: model.liveSystemText,
                                        symbol: "waveform"
                                    )
                                }

                                if !model.liveMicrophoneText.isEmpty {
                                    LiveDraftBubble(
                                        title: "You live",
                                        text: model.liveMicrophoneText,
                                        symbol: "mic.fill"
                                    )
                                }
                            }
                            .padding(.trailing, 4)
                        }
                        .frame(height: 186)
                    }
                }

                if let errorText = model.errorText {
                    DividerLine()
                    Text(errorText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .trailing, spacing: 10) {
                    if isShowingModelPicker {
                        ModelSelectionPopover(
                            model: model,
                            isVisible: $isShowingModelPicker
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    HStack {
                        StatusPill(text: model.statusText, symbol: "dot.radiowaves.left.and.right")
                        ModelSelectionButton(
                            model: model,
                            isVisible: $isShowingModelPicker
                        )
                        Spacer()
                    }
                }
            }
        }
    }

    private var inlineSettingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture {
                    isShowingSettings = false
                }

            SettingsView(model: model) {
                isShowingSettings = false
            }
            .frame(width: 560, height: 650)
        }
    }

    private var searchPromptPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.white.opacity(0.74))
            Text(searchPromptLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.white.opacity(0.92))
        }
        .font(.system(size: 15, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private var searchPromptLabel: String {
        if let latestScreenInsight = model.latestScreenInsight,
           latestScreenInsight.hasRecognizedText {
            let latestScreenHeadline = latestScreenInsight.headline
            return latestScreenHeadline
        }

        if let meetingLine = model.transcriptSegments.last(where: { $0.source == .systemAudio })?.text,
           !meetingLine.isEmpty {
            return meetingLine
        }

        return "Search the web for information..."
    }
}

struct SettingsView: View {
    @ObservedObject var model: GlassViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("OpenAI, capture, and live meeting behavior")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                SecureField("sk-...", text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("One OpenAI key powers both live transcription and the meeting copilot model.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Screen Access")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(model.screenAccessConfigured
                     ? "Screen Recording access is granted. Glass uses it for system audio capture and slide OCR, while still hiding its own overlay from screenshots and screen sharing."
                     : "Enable Screen Recording access to unlock system audio capture and OCR for shared slides. Glass still hides its own overlay from capture either way.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Model")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                SelectionOptionGrid(
                    options: OpenAITextModel.allCases,
                    selectedOption: model.selectedTextModel,
                    title: \.title,
                    subtitle: \.subtitle
                ) { option in
                    model.selectTextModel(option)
                }
                Text(model.selectedTextModel.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Thinking Capacity")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                SelectionOptionGrid(
                    options: OpenAIReasoningEffort.allCases,
                    selectedOption: model.selectedReasoningEffort,
                    title: \.title,
                    subtitle: nil
                ) { option in
                    model.selectReasoningEffort(option)
                }
                .opacity(model.selectedTextModel.supportsReasoningEffort ? 1 : 0.55)
                .allowsHitTesting(model.selectedTextModel.supportsReasoningEffort)
                Text(model.selectedTextModel.supportsReasoningEffort
                     ? "Applied to GPT-5 family meeting copilot responses."
                     : "This model uses standard inference, so thinking capacity is ignored.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Request Screen Access") {
                    model.requestScreenRecordingAccess()
                }
                Button("Relaunch Glass") {
                    model.relaunchApplication()
                }
                Button("Save Settings") {
                    if model.saveSettings() {
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
            }

            Spacer()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.32), radius: 28, y: 18)
    }
}

struct DarkGlassPanel<Content: View>: View {
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(width: width, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.52))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.13),
                                        Color.clear,
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 28, y: 18)
    }
}

struct ControlBarAction: View {
    let title: String
    let keyHints: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.white.opacity(0.96))

                if !keyHints.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(keyHints, id: \.self) { hint in
                            KeyCapView(title: hint)
                        }
                    }
                }
            }
            .font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(.plain)
    }
}

struct KeyCapView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            )
    }
}

struct AudioGlyph: View {
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach([8.0, 15.0, 11.0, 17.0, 9.0], id: \.self) { height in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 3, height: height)
            }
        }
    }
}

struct SessionElapsedText: View {
    let startDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(elapsedString(for: context.date))
                .monospacedDigit()
        }
    }

    private func elapsedString(for now: Date) -> String {
        guard let startDate else { return "00:00" }
        let elapsed = max(0, Int(now.timeIntervalSince(startDate)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ActionListButton: View {
    let title: String
    let symbol: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(.white.opacity(0.86))
                Text(title)
                    .foregroundStyle(.white.opacity(0.96))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(highlighted ? Color.white.opacity(0.18) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(highlighted ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatusPill: View {
    let text: String
    let symbol: String
    var showsDisclosureIndicator = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
            if showsDisclosureIndicator {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white.opacity(0.74))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

struct ModelSelectionButton: View {
    @ObservedObject var model: GlassViewModel
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                isVisible.toggle()
            }
        } label: {
            StatusPill(
                text: model.modelLine,
                symbol: "brain.head.profile",
                showsDisclosureIndicator: true
            )
        }
        .buttonStyle(.plain)
    }
}

struct ModelSelectionPopover: View {
    @ObservedObject var model: GlassViewModel
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Model Controls")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Model")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.52))
                SelectionOptionGrid(
                    options: OpenAITextModel.allCases,
                    selectedOption: model.selectedTextModel,
                    title: \.title,
                    subtitle: nil
                ) { option in
                    model.selectTextModel(option)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Thinking Capacity")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.52))
                SelectionOptionGrid(
                    options: OpenAIReasoningEffort.allCases,
                    selectedOption: model.selectedReasoningEffort,
                    title: \.title,
                    subtitle: nil
                ) { option in
                    model.selectReasoningEffort(option)
                }
                .opacity(model.selectedTextModel.supportsReasoningEffort ? 1 : 0.55)
                .allowsHitTesting(model.selectedTextModel.supportsReasoningEffort)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.34), radius: 22, y: 14)
    }
}

struct SelectionOptionGrid<Option: Identifiable & Equatable>: View {
    let options: [Option]
    let selectedOption: Option
    let title: KeyPath<Option, String>
    let subtitle: KeyPath<Option, String>?
    let onSelect: (Option) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(options) { option in
                Button {
                    onSelect(option)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(option[keyPath: title])
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.94))
                            Spacer(minLength: 0)
                            if option == selectedOption {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.86))
                            }
                        }

                        if let subtitle {
                            Text(option[keyPath: subtitle])
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.54))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(option == selectedOption ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(option == selectedOption ? Color.white.opacity(0.18) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CopilotHistoryView: View {
    @ObservedObject var model: GlassViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.copilotHistory.isEmpty {
                        CopilotResponseCard(
                            entry: CopilotResponseEntry(
                                advice: model.copilotAdvice,
                                createdAt: Date()
                            ),
                            isPlaceholder: true
                        )
                    } else {
                        ForEach(model.copilotHistory) { entry in
                            CopilotResponseCard(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .onChange(of: model.copilotHistory.count) { _, _ in
                guard let lastID = model.copilotHistory.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

struct CopilotResponseCard: View {
    let entry: CopilotResponseEntry
    var isPlaceholder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(isPlaceholder ? "Waiting for live context" : "AI update")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))

                Spacer()

                Text(isPlaceholder ? "Preview" : entry.timeLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Text(entry.advice.whatToSayNext)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.98))
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.advice.summary)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.advice.notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.white.opacity(0.78))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        Text(note)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(isPlaceholder ? 0.05 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(isPlaceholder ? 0.08 : 0.12), lineWidth: 1)
                )
        )
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

struct TranscriptBubble: View {
    let segment: TranscriptSegment

    private var accent: Color {
        switch segment.source {
        case .microphone:
            return Color.cyan.opacity(0.14)
        case .systemAudio:
            return Color.white.opacity(0.12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(segment.source.title, systemImage: segment.source.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.66))
                Spacer()
                Text(segment.timeLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Text(segment.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct LiveDraftBubble: View {
    let title: String
    let text: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .foregroundStyle(Color.white.opacity(0.16))
        )
    }
}

struct TranscriptPlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LeadingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private extension String {
    var glassTopicSeed: String {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "current topics" }
        let words = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        let snippet = words.prefix(4).joined(separator: " ")
        return snippet.lowercased()
    }
}
