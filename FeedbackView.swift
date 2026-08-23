import SwiftUI

enum FeedbackType: String, CaseIterable, Identifiable {
    case bug = "Bug Report"
    case feature = "Feature Request"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bug: return "ladybug"
        case .feature: return "lightbulb"
        }
    }

    var label: String { rawValue }

    var gitHubLabel: String {
        switch self {
        case .bug: return "bug"
        case .feature: return "enhancement"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .bug: return "What went wrong?"
        case .feature: return "What would you like to see?"
        }
    }

    var detailsPlaceholder: String {
        switch self {
        case .bug: return "Steps to reproduce, what you expected, what happened instead..."
        case .feature: return "Describe the feature and why it would be useful..."
        }
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType: FeedbackType = .bug
    @State private var title = ""
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $feedbackType) {
                        ForEach(FeedbackType.allCases) { type in
                            Text(type.label)
                                .tag(type)
                        }
                    }
                    .font(.nyBody)
                    .pickerStyle(.segmented)
                } header: {
                    Text("Feedback Type")
                        .font(.nyCaption)
                }

                Section {
                    TextField(feedbackType.titlePlaceholder, text: $title)
                        .font(.nyBody)
                } header: {
                    Text("Title")
                        .font(.nyCaption)
                }

                Section {
                    TextEditor(text: $details)
                        .font(.nyBody)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if details.isEmpty {
                                Text(feedbackType.detailsPlaceholder)
                                    .font(.nyBody)
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Details")
                        .font(.nyCaption)
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Submit Feedback")
                                    .font(.nyBody)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    .listRowBackground(
                        title.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.wineRed.opacity(0.3)
                            : Color.wineRed
                    )
                    .foregroundColor(.white)
                } footer: {
                    Text("Feedback is posted publicly as an issue on the app's GitHub page.")
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.nyBody)
                    .foregroundColor(.primary)
                }
            }
            .alert("Feedback Sent!", isPresented: $showingSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thanks for your feedback! We'll take a look.")
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
        }
    }

    private func submit() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let deviceInfo = """

        ---
        *Submitted from Pocket Somm app v\(version) (\(build))*
        *iOS \(systemVersion)*
        """

        let body = (details.isEmpty ? "*(No additional details provided)*" : details) + deviceInfo

        Task {
            do {
                try await GitHubService.createIssue(
                    title: "[\(feedbackType.label)] \(title)",
                    body: body,
                    labels: [feedbackType.gitHubLabel]
                )
                await MainActor.run {
                    isSubmitting = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    FeedbackView()
}
