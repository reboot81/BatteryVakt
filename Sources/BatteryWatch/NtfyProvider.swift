import Foundation

enum NtfyTopicValidation: Equatable {
    case empty, valid, tooLong, invalidCharacters
}

enum NtfyTopicValidator {
    static func validate(_ topic: String) -> NtfyTopicValidation {
        let clean = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .empty }
        guard clean.count <= 64 else { return .tooLong }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return clean.unicodeScalars.allSatisfy(allowed.contains) ? .valid : .invalidCharacters
    }
}

enum NtfyTopicGenerator {
    static func makeTopic() -> String {
        "batteryvakt-" + String(format: "%012llx", UInt64.random(in: 0...0xFFFF_FFFF_FFFF))
    }
}

enum NtfyError: LocalizedError {
    case invalidTopic, invalidResponse, server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidTopic: "Invalid ntfy topic."
        case .invalidResponse: "Invalid response from ntfy."
        case .server(let status): "ntfy returned HTTP \(status)."
        }
    }
}

struct NtfyProvider: Sendable {
    let topic: String

    func send(title: String, message: String, priority: Int, tags: [String]) async throws {
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NtfyTopicValidator.validate(cleanTopic) == .valid,
              let url = URL(string: "https://ntfy.sh/") else { throw NtfyError.invalidTopic }

        let body: [String: Any] = [
            "topic": cleanTopic, "title": title, "message": message,
            "priority": priority, "tags": tags
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NtfyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw NtfyError.server(http.statusCode) }
    }
}
