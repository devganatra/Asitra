import AuthenticationServices
import SwiftUI

struct AssistantChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var assistant = SakhyaAssistant()
    @State private var question = ""
    @State private var voiceCapture = VoiceCaptureService()
    @FocusState private var inputFocused: Bool

    private let suggestions: [AssistantSuggestion] = [
        AssistantSuggestion(title: "My day", prompt: "Tell me about today", icon: "sun.max", tint: .orange),
        AssistantSuggestion(title: "Patterns", prompt: "What stands out in my week?", icon: "sparkles", tint: .purple),
        AssistantSuggestion(title: "Life balance", prompt: "How is my work-life balance?", icon: "circle.lefthalf.filled", tint: .indigo),
        AssistantSuggestion(title: "Open items", prompt: "What needs my attention?", icon: "checklist", tint: .mint)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            conversation
            composer
        }
        .background(assistantBackground)
        .frame(minWidth: 430, idealWidth: 500, minHeight: 580, idealHeight: 680)
        .onChange(of: voiceCapture.transcript) { _, transcript in
            if voiceCapture.isRecording || voiceCapture.recordingURL != nil {
                question = transcript
            }
        }
        .onAppear {
            assistant.prepare(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.9), .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sakhya")
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text(assistant.serviceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                assistant.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New conversation")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(assistant.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if assistant.messages.count == 1 {
                        suggestionGrid
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        if !assistant.account.isConnected {
                            terraConnection
                        }
                        Label(
                            "Only grounded summaries needed for your question are sent to the shared Sakhya model.",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    }

                    if assistant.isResponding {
                        ThinkingRow()
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            .scrollIndicators(.hidden)
            .onChange(of: assistant.messages.count) { _, _ in
                if let last = assistant.messages.last {
                    withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var terraConnection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use the same AI everywhere")
                .font(.subheadline.weight(.semibold))
            Text("Connect with Apple to use Terra on Mac, iPhone, iPad and web. Your OpenAI key stays on Sakhya’s server.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                Task { await assistant.completeAppleAuthorization(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 42)
            .disabled(assistant.account.isConnecting)
            if assistant.account.isConnecting {
                ProgressView("Connecting Terra…")
                    .controlSize(.small)
            }
            if let error = assistant.account.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var suggestionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(suggestions) { suggestion in
                Button {
                    question = suggestion.prompt
                    send()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: suggestion.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(suggestion.tint)
                            .frame(width: 30, height: 30)
                            .background(suggestion.tint.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(suggestion.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .padding(13)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.primary.opacity(0.06))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about your day…", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.leading, 4)
                .padding(.vertical, 7)

            Button(action: toggleDictation) {
                Image(systemName: voiceCapture.isRecording ? "stop.fill" : "mic.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(voiceCapture.isRecording ? .white : .secondary)
                    .frame(width: 30, height: 30)
                    .background(voiceCapture.isRecording ? Color.red : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voiceCapture.isRecording ? "Stop dictating" : "Dictate question")

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary.opacity(0.25)
                            : Color.purple,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.isResponding)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(inputFocused ? 0.16 : 0.08))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var assistantBackground: some View {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }

    private func toggleDictation() {
        if voiceCapture.isRecording {
            voiceCapture.stop(discard: true)
        } else {
            Task { await voiceCapture.start() }
        }
    }

    private func send() {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if voiceCapture.isRecording { voiceCapture.stop(discard: true) }
        question = ""
        Task { await assistant.ask(value, model: model) }
    }
}

private struct AssistantSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let prompt: String
    let icon: String
    let tint: Color
}

private struct MessageBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 70) }

            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 26, height: 26)
                    .background(.purple.opacity(0.1), in: Circle())
            }

            messageText
                .padding(.horizontal, message.role == .user ? 13 : 0)
                .padding(.vertical, message.role == .user ? 9 : 2)
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.36, green: 0.27, blue: 0.78),
                                        Color(red: 0.29, green: 0.24, blue: 0.67)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .foregroundStyle(message.role == .user ? .white : .primary)

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity)
    }

    private var messageText: some View {
        Group {
            if let attributed = try? AttributedString(markdown: message.text) {
                Text(attributed)
            } else {
                Text(message.text)
            }
        }
        .font(.body)
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: 360, alignment: .leading)
    }
}

private struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 26, height: 26)
                .background(.purple.opacity(0.1), in: Circle())
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Reviewing your data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
