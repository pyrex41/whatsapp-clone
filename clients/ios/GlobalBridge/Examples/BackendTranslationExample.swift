//
//  BackendTranslationExample.swift
//  GlobalBridge
//
//  Real-world usage examples for BackendTranslationService
//  Demonstrates integration patterns for common scenarios
//

import SwiftUI

// MARK: - Example 1: Simple Message Translation

@MainActor
final class MessageTranslationViewModel: ObservableObject {
    @Published var originalMessage: String = ""
    @Published var translatedMessage: String?
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    @Published var translationResult: EnhancedTranslationResult?

    private let service = BackendTranslationService.shared

    func translateMessage(to targetLanguage: String) async {
        guard !originalMessage.isEmpty else { return }

        isTranslating = true
        errorMessage = nil

        do {
            let result = try await service.translate(
                text: originalMessage,
                targetLanguage: targetLanguage
            )

            translatedMessage = result.translatedText
            translationResult = result

            print("✅ Translation successful")
            print("Quality: \(result.qualityDescription)")
            if let notes = result.culturalNotes {
                print("Cultural notes: \(notes)")
            }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Translation error: \(error)")
        }

        isTranslating = false
    }
}

struct MessageTranslationView: View {
    @StateObject private var viewModel = MessageTranslationViewModel()
    @State private var targetLanguage = "es"

    var body: some View {
        VStack(spacing: 20) {
            Text("Message Translation")
                .font(.title)
                .fontWeight(.bold)

            TextEditor(text: $viewModel.originalMessage)
                .frame(height: 100)
                .border(Color.gray)
                .padding()

            Picker("Target Language", selection: $targetLanguage) {
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Japanese").tag("ja")
            }
            .pickerStyle(.segmented)

            Button("Translate") {
                Task {
                    await viewModel.translateMessage(to: targetLanguage)
                }
            }
            .disabled(viewModel.originalMessage.isEmpty || viewModel.isTranslating)

            if viewModel.isTranslating {
                ProgressView("Translating...")
            }

            if let translated = viewModel.translatedMessage {
                VStack(alignment: .leading) {
                    Text("Translation:")
                        .font(.headline)
                    Text(translated)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)

                    if let result = viewModel.translationResult {
                        TranslationMetadataView(result: result)
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Example 2: Conversation Thread Translation

@MainActor
final class ConversationTranslationViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var translationLanguage: String = "es"
    @Published var isTranslating: Bool = false

    private let service = BackendTranslationService.shared

    struct Message: Identifiable {
        let id = UUID()
        let text: String
        var translatedText: String?
        var isFromUser: Bool
    }

    func addMessage(_ text: String, isFromUser: Bool = true) {
        messages.append(Message(text: text, isFromUser: isFromUser))
    }

    func translateNewMessage(_ text: String) async {
        // Get recent messages for context
        let recentMessages = messages.suffix(5).map { $0.text }

        isTranslating = true

        do {
            let result = try await service.translate(
                text: text,
                targetLanguage: translationLanguage,
                context: recentMessages
            )

            print("✅ Context-aware translation: \(result.translatedText)")
            print("Context used: \(result.contextUsed)")

            addMessage(result.translatedText, isFromUser: false)
        } catch {
            print("❌ Translation error: \(error)")
        }

        isTranslating = false
    }

    func translateAllMessages() async {
        let textsToTranslate = messages.map { $0.text }

        isTranslating = true

        do {
            let results = try await service.batchTranslate(
                texts: textsToTranslate,
                targetLanguage: translationLanguage
            )

            for (index, result) in results.enumerated() {
                messages[index].translatedText = result.translatedText
            }

            print("✅ Batch translated \(results.count) messages")
        } catch {
            print("❌ Batch translation error: \(error)")
        }

        isTranslating = false
    }
}

struct ConversationTranslationView: View {
    @StateObject private var viewModel = ConversationTranslationViewModel()
    @State private var newMessageText = ""

    var body: some View {
        VStack {
            Text("Conversation Translation")
                .font(.title)
                .fontWeight(.bold)

            Picker("Language", selection: $viewModel.translationLanguage) {
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
            }
            .pickerStyle(.segmented)

            List(viewModel.messages) { message in
                VStack(alignment: message.isFromUser ? .trailing : .leading) {
                    Text(message.text)
                        .padding()
                        .background(message.isFromUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(8)

                    if let translated = message.translatedText {
                        Text(translated)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                TextField("Type message", text: $newMessageText)
                    .textFieldStyle(.roundedBorder)

                Button("Send & Translate") {
                    Task {
                        viewModel.addMessage(newMessageText, isFromUser: true)
                        await viewModel.translateNewMessage(newMessageText)
                        newMessageText = ""
                    }
                }
                .disabled(newMessageText.isEmpty || viewModel.isTranslating)
            }
            .padding()

            Button("Translate All") {
                Task {
                    await viewModel.translateAllMessages()
                }
            }
            .disabled(viewModel.messages.isEmpty || viewModel.isTranslating)
        }
    }
}

// MARK: - Example 3: Translation with Quality Feedback

@MainActor
final class QualityFeedbackViewModel: ObservableObject {
    @Published var translationResult: EnhancedTranslationResult?
    @Published var userRating: Int = 0
    @Published var feedbackIssues: Set<TranslationIssue> = []
    @Published var suggestedTranslation: String = ""

    private let service = BackendTranslationService.shared

    func translate(text: String, to targetLanguage: String) async {
        do {
            let result = try await service.translate(
                text: text,
                targetLanguage: targetLanguage
            )
            translationResult = result
        } catch {
            print("Error: \(error)")
        }
    }

    func submitFeedback() async {
        guard let result = translationResult else { return }

        await service.submitQualityFeedback(
            translationId: result.translationId,
            rating: userRating,
            issues: Array(feedbackIssues),
            suggestedTranslation: suggestedTranslation.isEmpty ? nil : suggestedTranslation
        )

        print("✅ Feedback submitted - Rating: \(userRating)/5")
    }
}

struct QualityFeedbackView: View {
    @StateObject private var viewModel = QualityFeedbackViewModel()

    var body: some View {
        VStack(spacing: 20) {
            if let result = viewModel.translationResult {
                Text("Translation:")
                    .font(.headline)
                Text(result.translatedText)
                    .padding()

                Text("Quality Score: \(String(format: "%.0f%%", result.qualityScore * 100))")
                Text("Confidence: \(String(format: "%.0f%%", result.confidence * 100))")

                Divider()

                Text("Rate this translation:")
                HStack {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= viewModel.userRating ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .onTapGesture {
                                viewModel.userRating = star
                            }
                    }
                }

                Text("Issues (optional):")
                ForEach([TranslationIssue.wrongMeaning, .awkwardPhrasing, .missingContext, .incorrectFormality], id: \.self) { issue in
                    Toggle(issue.rawValue.replacingOccurrences(of: "_", with: " "), isOn: Binding(
                        get: { viewModel.feedbackIssues.contains(issue) },
                        set: { isOn in
                            if isOn {
                                viewModel.feedbackIssues.insert(issue)
                            } else {
                                viewModel.feedbackIssues.remove(issue)
                            }
                        }
                    ))
                }

                TextField("Suggested translation", text: $viewModel.suggestedTranslation)
                    .textFieldStyle(.roundedBorder)

                Button("Submit Feedback") {
                    Task {
                        await viewModel.submitFeedback()
                    }
                }
                .disabled(viewModel.userRating == 0)
            }
        }
        .padding()
    }
}

// MARK: - Example 4: Translation History Dashboard

@MainActor
final class TranslationHistoryViewModel: ObservableObject {
    @Published var history: [TranslationHistoryEntry] = []
    @Published var statistics: TranslationStatistics?

    private let service = BackendTranslationService.shared

    func loadHistory() {
        history = service.getTranslationHistory(limit: 50)
        statistics = service.getStatistics()
    }

    func clearHistory() {
        service.clearTranslationHistory()
        loadHistory()
    }
}

struct TranslationHistoryView: View {
    @StateObject private var viewModel = TranslationHistoryViewModel()

    var body: some View {
        VStack {
            Text("Translation History")
                .font(.title)
                .fontWeight(.bold)

            if let stats = viewModel.statistics {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Statistics")
                        .font(.headline)

                    HStack {
                        Text("Total translations:")
                        Spacer()
                        Text("\(stats.totalTranslations)")
                            .fontWeight(.bold)
                    }

                    HStack {
                        Text("Average confidence:")
                        Spacer()
                        Text(String(format: "%.0f%%", stats.averageConfidence * 100))
                            .fontWeight(.bold)
                    }

                    HStack {
                        Text("Average rating:")
                        Spacer()
                        Text(String(format: "%.1f/5", stats.averageRating))
                            .fontWeight(.bold)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }

            List(viewModel.history, id: \.timestamp) { entry in
                VStack(alignment: .leading) {
                    Text(entry.originalText)
                        .font(.body)
                    Text(entry.translatedText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(entry.sourceLanguage) → \(entry.targetLanguage)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            Button("Clear History") {
                viewModel.clearHistory()
            }
            .foregroundColor(.red)
        }
        .onAppear {
            viewModel.loadHistory()
        }
    }
}

// MARK: - Supporting Views

struct TranslationMetadataView: View {
    let result: EnhancedTranslationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Confidence:")
                Text("\(Int(result.confidence * 100))%")
                    .fontWeight(.bold)
            }

            HStack {
                Text("Quality:")
                Text(result.qualityDescription)
                    .fontWeight(.bold)
                    .foregroundColor(result.isHighQuality ? .green : .orange)
            }

            if let formality = result.formality {
                HStack {
                    Text("Formality:")
                    Text(formality.rawValue)
                        .fontWeight(.bold)
                }
            }

            if result.contextUsed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Context-aware translation")
                        .font(.caption)
                }
            }

            if let notes = result.culturalNotes {
                VStack(alignment: .leading) {
                    Text("Cultural Notes:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(notes)
                        .font(.caption)
                        .italic()
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Preview Provider

struct BackendTranslationExamples_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            MessageTranslationView()
                .tabItem {
                    Label("Simple", systemImage: "text.bubble")
                }

            ConversationTranslationView()
                .tabItem {
                    Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                }

            QualityFeedbackView()
                .tabItem {
                    Label("Feedback", systemImage: "star")
                }

            TranslationHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
        }
    }
}
