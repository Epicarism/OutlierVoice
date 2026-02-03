import Foundation

/// Protocol for LLM clients
protocol LLMClient: Sendable {
    func chat(messages: [ChatMessage], model: LLMModel) async throws -> AsyncThrowingStream<String, Error>
}

/// Conversation from Outlier API
struct OutlierConversation: Codable, Identifiable {
    let id: String
    let title: String?
    let createdAt: String?
    let updatedAt: String?
    let isStarred: Bool?
    
    var displayTitle: String {
        title ?? "Untitled"
    }
}

/// Outlier API client for chat completions
actor OutlierClient: LLMClient {
    private let baseURL = "https://app.outlier.ai/internal/experts/assistant"
    private var cookie: String = ""
    private var csrfToken: String = ""
    private let session: URLSession
    
    /// Whether to enable Claude's extended thinking (adds latency but improves reasoning)
    var enableThinking: Bool {
        // Default to OFF for voice (latency matters more than deep reasoning)
        UserDefaults.standard.bool(forKey: "enableThinking")
    }
    
    enum OutlierError: LocalizedError {
        case notAuthenticated
        case requestFailed(String)
        case invalidResponse
        case streamingError(String)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated. Please log in via Settings."
            case .requestFailed(let reason):
                return "Request failed: \(reason)"
            case .invalidResponse:
                return "Invalid response from server"
            case .streamingError(let reason):
                return "Streaming error: \(reason)"
            }
        }
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        
        // Load saved credentials inline (can't call actor-isolated method from init)
        self.cookie = UserDefaults.standard.string(forKey: "outlier_cookie") ?? ""
        self.csrfToken = UserDefaults.standard.string(forKey: "outlier_csrf") ?? ""
        print("[OutlierClient] Loaded credentials - cookie has _jwt: \(cookie.contains("_jwt=")), csrf length: \(csrfToken.count)")
    }
    
    // MARK: - Credential Management
    
    private func reloadCredentials() {
        cookie = UserDefaults.standard.string(forKey: "outlier_cookie") ?? ""
        csrfToken = UserDefaults.standard.string(forKey: "outlier_csrf") ?? ""
        print("[OutlierClient] Reloaded credentials - cookie has _jwt: \(cookie.contains("_jwt=")), csrf length: \(csrfToken.count)")
    }
    
    func setCredentials(cookie: String, csrf: String) {
        self.cookie = cookie
        self.csrfToken = csrf
        UserDefaults.standard.set(cookie, forKey: "outlier_cookie")
        UserDefaults.standard.set(csrf, forKey: "outlier_csrf")
        print("[OutlierClient] Saved credentials - cookie has _jwt: \(cookie.contains("_jwt=")), csrf length: \(csrf.count)")
    }
    
    func getCredentials() -> (cookie: String, csrf: String) {
        return (cookie, csrfToken)
    }
    
    func isAuthenticated() -> Bool {
        return !cookie.isEmpty && cookie.contains("_jwt=")
    }
    
    /// Test if credentials are actually working by hitting the /allowed endpoint
    func testCredentials() async -> (working: Bool, reason: String) {
        guard isAuthenticated() else {
            return (false, "No credentials set")
        }
        
        guard let url = URL(string: "\(baseURL)/allowed") else {
            return (false, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response")
            }
            
            let responseText = String(data: data, encoding: .utf8) ?? ""
            print("[OutlierClient] /allowed response: \(httpResponse.statusCode) - \(responseText.prefix(200))")
            
            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let allowed = json["allowed"] as? Bool {
                    return (allowed, allowed ? "Allowed" : "Not allowed: \(json["reasons"] ?? "unknown")")
                }
                return (true, "OK")
            } else if httpResponse.statusCode == 401 {
                return (false, "Unauthorized - credentials expired")
            } else {
                return (false, "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    func clearCredentials() {
        cookie = ""
        csrfToken = ""
        currentConversationId = nil
        UserDefaults.standard.removeObject(forKey: "outlier_cookie")
        UserDefaults.standard.removeObject(forKey: "outlier_csrf")
    }
    
    // MARK: - Request Helpers
    
    /// Build headers matching the VSCode extension exactly
    private func buildHeaders(streaming: Bool = false) -> [String: String] {
        return [
            "Content-Type": "application/json",
            "Cookie": cookie,
            "X-CSRF-Token": csrfToken,
            "Origin": "https://app.outlier.ai",
            "Referer": "https://app.outlier.ai/",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Accept": streaming ? "text/event-stream" : "application/json, text/plain, */*"
        ]
    }
    
    private func applyHeaders(to request: inout URLRequest, streaming: Bool = false) {
        for (key, value) in buildHeaders(streaming: streaming) {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
    
    // MARK: - Conversation Management
    
    private var currentConversationId: String?
    
    /// Create a new conversation (required before sending messages)
    /// Tries the requested model first, then falls back to alternatives on 500 errors
    func createConversation(model: LLMModel = .opus45) async throws -> String {
        guard isAuthenticated() else {
            throw OutlierError.notAuthenticated
        }
        
        // Models to try in order (requested model first, then fallbacks)
        let modelsToTry: [LLMModel] = {
            var models = [model]
            // Add fallbacks if not already the requested model
            if model != .gemini3Flash { models.append(.gemini3Flash) }
            if model != .glm47 { models.append(.glm47) }
            if model != .gpt52 { models.append(.gpt52) }
            return models
        }()
        
        var lastError: Error?
        
        for tryModel in modelsToTry {
            do {
                let convId = try await createConversationInternal(model: tryModel)
                if tryModel != model {
                    print("[OutlierClient] ⚠️ Used fallback model: \(tryModel.apiIdentifier) (requested: \(model.apiIdentifier))")
                }
                return convId
            } catch let error as OutlierError {
                lastError = error
                // Only retry on 500 errors (server issues)
                if case .requestFailed(let msg) = error, msg.contains("500") {
                    print("[OutlierClient] Model \(tryModel.apiIdentifier) failed with 500, trying next...")
                    continue
                }
                // For other errors, don't retry
                throw error
            } catch {
                lastError = error
                throw error
            }
        }
        
        throw lastError ?? OutlierError.requestFailed("All models failed")
    }
    
    private func createConversationInternal(model: LLMModel) async throws -> String {
        guard let url = URL(string: "\(baseURL)/conversations/") else {
            throw OutlierError.requestFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        
        let body: [String: Any] = [
            "model": model.apiIdentifier,
            "prompt": ["text": "", "images": []],
            "challengeId": NSNull()
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("[OutlierClient] Creating conversation with model: \(model.apiIdentifier)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlierError.invalidResponse
        }
        
        let responseText = String(data: data, encoding: .utf8) ?? ""
        print("[OutlierClient] createConversation response: \(httpResponse.statusCode) - \(responseText.prefix(200))")
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw OutlierError.requestFailed("HTTP \(httpResponse.statusCode): \(responseText)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let convId = json["id"] as? String else {
            throw OutlierError.requestFailed("No conversation ID in response")
        }
        
        currentConversationId = convId
        currentModel = model
        print("[OutlierClient] ✓ Created conversation: \(convId) with model: \(model.apiIdentifier)")
        return convId
    }
    
    private var currentModel: LLMModel = .opus45
    
    func getCurrentModel() -> LLMModel {
        return currentModel
    }
    
    func getCurrentConversationId() -> String? {
        return currentConversationId
    }
    
    func setCurrentConversationId(_ id: String?) {
        currentConversationId = id
    }
    
    // MARK: - Conversations API
    
    func fetchConversations() async throws -> [OutlierConversation] {
        guard isAuthenticated() else {
            throw OutlierError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/conversations/") else {
            throw OutlierError.requestFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        
        print("[OutlierClient] Fetching conversations...")
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlierError.invalidResponse
        }
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw OutlierError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let conversations = try JSONDecoder().decode([OutlierConversation].self, from: data)
        return conversations
    }
    
    func fetchConversationMessages(convId: String) async throws -> [[String: Any]] {
        guard isAuthenticated() else {
            throw OutlierError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/conversations/\(convId)") else {
            throw OutlierError.requestFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        
        print("[OutlierClient] Loading conversation \(convId)...")
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlierError.invalidResponse
        }
        
        let responseText = String(data: data, encoding: .utf8) ?? ""
        print("[OutlierClient] fetchConversationMessages response: \(httpResponse.statusCode) - \(responseText.prefix(300))")
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw OutlierError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OutlierError.invalidResponse
        }
        
        // API returns "turns" not "messages"
        if let turns = json["turns"] as? [[String: Any]] {
            print("[OutlierClient] Loaded \(turns.count) turns")
            // DEBUG: Log full structure to find thinking fields
            if let firstTurn = turns.first {
                print("[OutlierClient] 📋 Turn keys: \(firstTurn.keys.sorted())")
                if let responses = firstTurn["responses"] as? [[String: Any]], let firstResp = responses.first {
                    print("[OutlierClient] 📋 Response keys: \(firstResp.keys.sorted())")
                }
            }
            return turns
        }
        
        // Fallback to messages if turns not present
        if let messages = json["messages"] as? [[String: Any]] {
            print("[OutlierClient] Loaded \(messages.count) messages")
            return messages
        }
        
        print("[OutlierClient] No turns or messages found in response")
        return []
    }
    
    // MARK: - Image Upload to CDS
    
    func uploadImage(data: Data, fileName: String) async throws -> String {
        print("[OutlierClient] uploadImage called - data size: \(data.count) bytes, fileName: \(fileName)")
        
        guard isAuthenticated() else {
            print("[OutlierClient] ERROR: Not authenticated for image upload")
            throw OutlierError.notAuthenticated
        }
        
        // Determine MIME type
        let ext = fileName.lowercased().components(separatedBy: ".").last ?? "jpg"
        let mimeTypes: [String: String] = [
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "webp": "image/webp",
            "gif": "image/gif"
        ]
        let mimeType = mimeTypes[ext] ?? "image/jpeg"
        
        // Build multipart form data
        let boundary = "----WebKitFormBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        
        var body = Data()
        
        // Image file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"imageFile\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        
        // Conversation ID part (must be null for image upload)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"conversationId\"\r\n\r\n".data(using: .utf8)!)
        body.append("null\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        guard let url = URL(string: "\(baseURL)/images") else {
            throw OutlierError.requestFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        request.setValue("https://app.outlier.ai", forHTTPHeaderField: "Origin")
        request.httpBody = body
        
        print("[OutlierClient] Sending image upload request...")
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[OutlierClient] ERROR: Invalid response type")
            throw OutlierError.invalidResponse
        }
        
        print("[OutlierClient] Upload response: HTTP \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorText = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            print("[OutlierClient] ERROR: Upload failed - \(errorText)")
            throw OutlierError.requestFailed("Upload failed: HTTP \(httpResponse.statusCode) - \(errorText)")
        }
        
        // Parse response - should be a CDS URL like "scale-cds://..."
        var urlString = String(data: responseData, encoding: .utf8) ?? ""
        urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        urlString = urlString.replacingOccurrences(of: "\"", with: "")
        
        print("[OutlierClient] Upload response URL: \(urlString)")
        
        guard urlString.hasPrefix("scale-cds://") else {
            print("[OutlierClient] ERROR: Unexpected response format")
            throw OutlierError.requestFailed("Unexpected response: \(urlString)")
        }
        
        print("[OutlierClient] Image uploaded successfully: \(urlString)")
        return urlString
    }
    
    // MARK: - Chat with Images
    
    func chatWithImages(prompt: String, imageUrls: [(url: String, mimeType: String, name: String)], model: LLMModel) async throws -> AsyncThrowingStream<String, Error> {
        guard isAuthenticated() else {
            throw OutlierError.notAuthenticated
        }
        
        // Create conversation if we don't have one
        if currentConversationId == nil {
            _ = try await createConversation(model: model)
        }
        
        guard let convId = currentConversationId else {
            throw OutlierError.requestFailed("Failed to create conversation")
        }
        
        // Use the same turn-streaming endpoint as regular chat
        guard let url = URL(string: "\(baseURL)/conversations/\(convId)/turn-streaming") else {
            throw OutlierError.requestFailed("Invalid URL")
        }
        
        let actualModel = currentModel
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, streaming: true)
        
        // Build images array for request
        let imagesPayload = imageUrls.map { img in
            ["url": img.url, "mimeType": img.mimeType, "name": img.name]
        }
        
        // Build request body matching the VSCode extension format
        let thinkingEnabled = enableThinking
        
        let body: [String: Any] = [
            "prompt": [
                "text": prompt,
                "model": actualModel.apiIdentifier,
                "images": imagesPayload,
                "systemMessage": "You are a concise voice assistant for a software developer. Keep responses brief and direct since they will be spoken aloud via text-to-speech. Avoid asterisks, markdown formatting, bullet points, and symbols. Use plain conversational English. When describing code, speak it naturally rather than using formatting. Minimize emoji usage.",
                "enableThinking": thinkingEnabled
            ],
            "model": actualModel.apiIdentifier,
            "systemMessage": "You are a concise voice assistant for a software developer. Keep responses brief and direct since they will be spoken aloud via text-to-speech. Avoid asterisks, markdown formatting, bullet points, and symbols. Use plain conversational English. When describing code, speak it naturally rather than using formatting. Minimize emoji usage.",
            "turnType": "Text",
            "parentTurnIdx": 0,
            "isBattle": false,
            "max_tokens": 8192
        ]
        
        print("[OutlierClient] Sending message with \(imageUrls.count) images to conversation \(convId)")
        print("[OutlierClient] Model: \(actualModel.apiIdentifier)")
        print("[OutlierClient] Prompt: \(prompt.prefix(100))...")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OutlierError.invalidResponse)
                        return
                    }
                    
                    guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                        continuation.finish(throwing: OutlierError.requestFailed("HTTP \(httpResponse.statusCode)"))
                        return
                    }
                    
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))
                        
                        if data == "[DONE]" { break }
                        
                        if let jsonData = data.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            if let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any] {
                                
                                // Extract THINKING from reasoning_content
                                if let reasoningContent = delta["reasoning_content"] as? String,
                                   !reasoningContent.isEmpty {
                                    print("[OutlierClient] 🧠 Image chat thinking: \(reasoningContent.prefix(30))...")
                                    continuation.yield("🧠THINKING🧠\(reasoningContent)")
                                }
                                
                                // Extract regular content
                                if let content = delta["content"] as? String,
                                   !content.isEmpty {
                                    continuation.yield(content)
                                }
                            } else if let text = json["text"] as? String {
                                continuation.yield(text)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    // MARK: - Chat API
    
    /// Send a message to the current conversation (creates one if needed)
    func chat(messages: [ChatMessage], model: LLMModel) async throws -> AsyncThrowingStream<String, Error> {
        guard isAuthenticated() else {
            throw OutlierError.notAuthenticated
        }
        
        // Create conversation if we don't have one
        if currentConversationId == nil {
            _ = try await createConversation(model: model)
        }
        
        guard let convId = currentConversationId else {
            throw OutlierError.requestFailed("Failed to create conversation")
        }
        
        // Use the model that was actually used to create the conversation (might be fallback)
        let actualModel = currentModel
        
        // Use turn-streaming endpoint like the VSCode extension
        guard let url = URL(string: "\(baseURL)/conversations/\(convId)/turn-streaming") else {
            throw OutlierError.requestFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, streaming: true)
        
        // Get the last user message as the prompt
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        
        // Build request body matching the VSCode extension format EXACTLY
        let thinkingEnabled = enableThinking
        print("[OutlierClient] Thinking enabled: \(thinkingEnabled)")
        
        let body: [String: Any] = [
            "prompt": [
                "text": lastUserMessage,
                "model": actualModel.apiIdentifier,
                "images": [],
                "systemMessage": "You are a concise voice assistant for a software developer. Keep responses brief and direct since they will be spoken aloud via text-to-speech. Avoid asterisks, markdown formatting, bullet points, and symbols. Use plain conversational English. When describing code, speak it naturally rather than using formatting. Minimize emoji usage.",
                "enableThinking": thinkingEnabled
            ],
            "model": actualModel.apiIdentifier,
            "systemMessage": "You are a concise voice assistant for a software developer. Keep responses brief and direct since they will be spoken aloud via text-to-speech. Avoid asterisks, markdown formatting, bullet points, and symbols. Use plain conversational English. When describing code, speak it naturally rather than using formatting. Minimize emoji usage.",
            "turnType": "Text",
            "parentTurnIdx": 0,
            "isBattle": false,
            "max_tokens": 8192
        ]
        
        print("[OutlierClient] Sending message to conversation \(convId)")
        print("[OutlierClient] Model: \(actualModel.apiIdentifier)")
        print("[OutlierClient] Prompt: \(lastUserMessage.prefix(100))...")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OutlierError.invalidResponse)
                        return
                    }
                    
                    // 200 OK or 201 Created are both success for streaming
                    guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                        // Try to read error body
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 500 { break }
                        }
                        print("[OutlierClient] ❌ HTTP \(httpResponse.statusCode): \(errorBody)")
                        continuation.finish(throwing: OutlierError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)"))
                        return
                    }
                    
                    print("[OutlierClient] ✓ Streaming response started")
                    
                    // Parse SSE stream
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))
                        
                        if data == "[DONE]" {
                            break
                        }
                        
                        if let jsonData = data.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            
                            // Parse choices[0].delta
                            if let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any] {
                                
                                // DEBUG: Log all delta keys
                                print("[OutlierClient] 📦 Delta keys: \(delta.keys.sorted())")
                                
                                // Extract THINKING from reasoning_content (Outlier/Anthropic format)
                                if let reasoningContent = delta["reasoning_content"] as? String,
                                   !reasoningContent.isEmpty {
                                    print("[OutlierClient] 🧠 THINKING FOUND: '\(reasoningContent.prefix(50))...'")
                                    continuation.yield("🧠THINKING🧠\(reasoningContent)")
                                }
                                
                                // Extract regular content
                                if let content = delta["content"] as? String,
                                   !content.isEmpty {
                                    print("[OutlierClient] 💬 Content: '\(content.prefix(30))...'")
                                    continuation.yield(content)
                                }
                            }
                            // Fallback formats
                            else if let text = json["text"] as? String {
                                continuation.yield(text)
                            } else if let content = json["content"] as? String {
                                continuation.yield(content)
                            }
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
}

// MARK: - Non-streaming fallback

extension OutlierClient {
    func chatSync(messages: [ChatMessage], model: LLMModel) async throws -> String {
        var result = ""
        
        for try await chunk in try await chat(messages: messages, model: model) {
            result += chunk
        }
        
        return result
    }
}
