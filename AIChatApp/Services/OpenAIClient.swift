import Foundation

struct OpenAIClient {
    private let configuration: ChatConfiguration
    private let decoder = JSONDecoder()

    init(configuration: ChatConfiguration) {
        self.configuration = configuration
    }

    func streamChat(messages: [ChatMessage]) async throws -> AsyncThrowingStream<String, Error> {
        let request = try makeRequest(messages: messages, stream: true)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try await validate(response: response, bytes: bytes)

                    for try await line in bytes.lines {
                        let payload = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard payload.hasPrefix("data:") else {
                            continue
                        }

                        let dataString = payload
                            .dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if dataString == "[DONE]" {
                            break
                        }

                        guard let data = dataString.data(using: .utf8) else {
                            continue
                        }

                        let chunk = try decoder.decode(ChatCompletionChunk.self, from: data)
                        if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 非流式:一次性返回完整回复内容。
    func completeChat(messages: [ChatMessage]) async throws -> String {
        let request = try makeRequest(messages: messages, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data, decoder: decoder)
        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        return completion.choices.first?.message.content ?? ""
    }

    static func fetchModels(using configuration: APIConnectionConfiguration) async throws -> [String] {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else {
            throw SettingsError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        try validate(response: response, data: data, decoder: decoder)

        let list = try decoder.decode(ModelListResponse.self, from: data)
        return Array(Set(list.data.map(\.id))).sorted()
    }

    private func makeRequest(messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw SettingsError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")

        var requestMessages: [OpenAIMessage] = []
        if !configuration.systemPrompt.isEmpty {
            requestMessages.append(OpenAIMessage(
                role: ChatMessage.Role.system.rawValue,
                content: .text(configuration.systemPrompt)
            ))
        }
        requestMessages.append(contentsOf: try messages.map { message in
            try makeOpenAIMessage(from: message)
        })

        let payload = ChatCompletionRequest(
            model: configuration.model,
            messages: requestMessages,
            temperature: configuration.temperature,
            topP: configuration.topP,
            maxTokens: configuration.maxTokens,
            stream: stream
        )

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func makeOpenAIMessage(from message: ChatMessage) throws -> OpenAIMessage {
        guard !message.attachments.isEmpty else {
            return OpenAIMessage(role: message.role.rawValue, content: .text(message.content))
        }

        var parts: [OpenAIContentPart] = []
        if !message.content.isEmpty {
            parts.append(.text(message.content))
        }

        for attachment in message.attachments {
            let dataURL = try AttachmentStore.dataURL(for: attachment)
            switch attachment.kind {
            case .image:
                parts.append(.imageURL(url: dataURL))
            case .file:
                parts.append(.file(filename: attachment.filename, fileData: dataURL))
            }
        }

        return OpenAIMessage(role: message.role.rawValue, content: .parts(parts))
    }

    private func validate(response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
            }

            if let apiError = try? decoder.decode(OpenAIErrorResponse.self, from: body) {
                throw OpenAIClientError.server(statusCode: httpResponse.statusCode, message: apiError.error.message)
            }

            let message = String(data: body, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIClientError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private static func validate(response: URLResponse, data: Data, decoder: JSONDecoder) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? decoder.decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIClientError.server(statusCode: httpResponse.statusCode, message: apiError.error.message)
            }

            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIClientError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

enum OpenAIClientError: LocalizedError {
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .server(statusCode, message):
            return "请求失败（\(statusCode)）：\(message)"
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case stream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encode(stream, forKey: .stream)
    }
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: OpenAIMessageContent
}

private enum OpenAIMessageContent: Encodable {
    case text(String)
    case parts([OpenAIContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text):
            try container.encode(text)
        case let .parts(parts):
            try container.encode(parts)
        }
    }
}

private enum OpenAIContentPart: Encodable {
    case text(String)
    case imageURL(url: String)
    case file(filename: String, fileData: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case file
    }

    private struct ImageURLPayload: Encodable {
        let url: String
    }

    private struct FilePayload: Encodable {
        let filename: String
        let fileData: String

        private enum CodingKeys: String, CodingKey {
            case filename
            case fileData = "file_data"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: url), forKey: .imageURL)
        case let .file(filename, fileData):
            try container.encode("file", forKey: .type)
            try container.encode(
                FilePayload(filename: filename, fileData: fileData),
                forKey: .file
            )
        }
    }
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

private struct ModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
