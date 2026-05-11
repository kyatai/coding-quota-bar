import Foundation

// MARK: - HTTP Client with Retry

actor HttpClient {
    private let session: URLSession
    private let maxRetries: Int
    private let baseDelay: TimeInterval

    init(maxRetries: Int = 3, baseDelay: TimeInterval = 1.0) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func get(url: String, headers: [String: String] = [:]) async throws -> Data {
        guard let requestUrl = URL(string: url) else {
            throw HttpError.invalidURL(url)
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw HttpError.invalidResponse
                }
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    return data
                }
                if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                    lastError = HttpError.httpError(httpResponse.statusCode)
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw HttpError.httpError(httpResponse.statusCode)
            } catch let error as HttpError {
                lastError = error
                let delay = baseDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                lastError = error
                let delay = baseDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError ?? HttpError.maxRetriesExceeded
    }

    enum HttpError: LocalizedError {
        case invalidURL(String)
        case invalidResponse
        case httpError(Int)
        case maxRetriesExceeded

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid URL: \(url)"
            case .invalidResponse: return "Invalid response"
            case .httpError(let code): return "HTTP Error: \(code)"
            case .maxRetriesExceeded: return "Max retries exceeded"
            }
        }
    }
}
