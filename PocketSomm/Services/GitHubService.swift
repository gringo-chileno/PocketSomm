import Foundation

struct GitHubService {
    private static let token = Secrets.githubPAT
    private static let owner = "gringo-chileno"
    private static let repo = "PocketSomm"

    static var isConfigured: Bool {
        !token.isEmpty
    }

    static func createIssue(title: String, body: String, labels: [String]) async throws {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "labels": labels
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    enum GitHubError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from GitHub"
            case .apiError(let statusCode, let message):
                return "GitHub API error (HTTP \(statusCode)): \(message)"
            }
        }
    }
}
