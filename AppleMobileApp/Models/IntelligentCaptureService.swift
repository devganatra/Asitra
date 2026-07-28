import AVFoundation
import Foundation
import ImageIO
import Observation
import Speech
import Vision

struct ImageCaptureAnalysis: Sendable {
    let recognizedText: String
    let labels: [String]
    let suggestedCapture: String
}

enum ImageIntelligenceService {
    static func analyze(_ data: Data) async throws -> ImageCaptureAnalysis {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw IntelligentCaptureError.invalidImage
            }

            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true

            let classificationRequest = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([textRequest, classificationRequest])

            let lines = (textRequest.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let labels = (classificationRequest.results ?? [])
                .filter { $0.confidence >= 0.15 }
                .prefix(5)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }

            return ImageCaptureAnalysis(
                recognizedText: lines.prefix(16).joined(separator: "\n"),
                labels: labels,
                suggestedCapture: suggestedCapture(from: lines, labels: labels)
            )
        }.value
    }

    private static func suggestedCapture(from lines: [String], labels: [String]) -> String {
        let allText = lines.joined(separator: " ")
        let lowercased = allText.lowercased()
        let labelText = labels.joined(separator: " ").lowercased()

        if lowercased.contains("total") || lowercased.contains("receipt") || lowercased.contains("invoice") {
            let merchant = lines.first.map(shortened) ?? "purchase"
            if let total = receiptTotal(in: lines) {
                return "Spent " + total + " at " + merchant
            }
            return "Receipt from " + merchant + ": " + shortened(allText)
        }

        if labelText.contains("book") || labelText.contains("textbook") {
            return "Book: " + shortened(allText.isEmpty ? labels.joined(separator: ", ") : allText)
        }

        if labelText.contains("food") || labelText.contains("dish") || labelText.contains("meal") {
            return "Ate " + shortened(labels.prefix(3).joined(separator: ", "))
        }

        if !allText.isEmpty {
            return "Note from photo: " + shortened(allText)
        }

        if !labels.isEmpty {
            return "Photo of " + labels.prefix(3).joined(separator: ", ")
        }

        return "Photo note"
    }

    private static func receiptTotal(in lines: [String]) -> String? {
        let totalLines = lines.filter { $0.lowercased().contains("total") }.reversed()
        let pattern = #"(?:€|\$|£)?\s*\d+[\.,]\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        for line in totalLines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.matches(in: line, range: range).last,
                  let matchRange = Range(match.range, in: line) else { continue }
            return String(line[matchRange]).replacingOccurrences(of: " ", with: "")
        }
        return nil
    }

    private static func shortened(_ value: String) -> String {
        let compact = value.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        return compact.count > 160 ? String(compact.prefix(157)) + "…" : compact
    }
}

@MainActor
@Observable
final class VoiceCaptureService {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var recordingURL: URL?
    private(set) var usesOnDeviceRecognition = false
    private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        recordingURL = nil

        guard await requestSpeechPermission() else {
            errorMessage = "Allow Speech Recognition in System Settings to transcribe voice notes."
            return
        }
        guard await requestMicrophonePermission() else {
            errorMessage = "Allow microphone access in System Settings to record voice notes."
            return
        }

        do {
#if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
            guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
                throw IntelligentCaptureError.speechUnavailable
            }

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            usesOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.requiresOnDeviceRecognition = usesOnDeviceRecognition

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw IntelligentCaptureError.microphoneUnavailable }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sakhya-voice-" + UUID().uuidString)
                .appendingPathExtension("m4a")
            let recordingSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: max(Int(format.channelCount), 1),
                AVEncoderBitRateKey: 64_000
            ]
            let file = try AVAudioFile(forWriting: url, settings: recordingSettings)

            recognitionTask?.cancel()
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result {
                        self?.transcript = result.bestTranscription.formattedString
                    }
                    if let error, self?.isRecording == true {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                try? file.write(from: buffer)
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()
            audioEngine = engine
            audioFile = file
            recognitionRequest = request
            recordingURL = url
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            stop(discard: true)
        }
    }

    func stop(discard: Bool = false) {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        audioEngine = nil
        audioFile = nil
        recognitionRequest = nil
        isRecording = false

#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif

        if discard {
            recognitionTask?.cancel()
            if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
            recordingURL = nil
            transcript = ""
        }
    }

    func reset() {
        stop(discard: true)
        errorMessage = nil
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
#if os(macOS)
        return await AVCaptureDevice.requestAccess(for: .audio)
#else
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
#endif
    }
}

enum IntelligentCaptureError: LocalizedError {
    case invalidImage
    case speechUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Sakhya could not read this image."
        case .speechUnavailable: "Speech recognition is currently unavailable."
        case .microphoneUnavailable: "No microphone input is available."
        }
    }
}
