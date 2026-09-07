import Foundation
import PineappleCore

protocol AIHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
struct URLSessionTransport: AIHTTPTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 240
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.ai("AI 服务返回了无法识别的响应。") }
        return (data, http)
    }
}

struct AIMessage: Codable, Sendable {
    var role: String
    var content: String
}
private struct CompletionRequest: Encodable {
    var model: String
    var messages: [AIMessage]
    var stream = false
    var max_tokens: Int
    var response_format: [String: String] = ["type": "json_object"]
    var thinking: [String: String]
    var reasoning_effort: String?
}
private struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String? }
        var message: Message
        var finish_reason: String?
    }
    var choices: [Choice]
}

struct DeepSeekService: Sendable {
    let transport: any AIHTTPTransport
    init(transport: any AIHTTPTransport = URLSessionTransport()) { self.transport = transport }

    func structured<T: Decodable & Sendable>(_: T.Type, task: AITask, question: String,
                                             messages: [AIMessage], settings: UserSettings, apiKey: String,
                                             validate: @Sendable (T) throws -> Void) async throws -> T {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.ai("请先在设置中保存 DeepSeek API Key。") }
        let mode = AIRouter.resolve(settings.aiMode, task: task, question: question)
        var conversation = messages
        // A malformed response gets exactly one structured repair attempt, never a local write.
        for attempt in 0...1 {
            try Task.checkCancellation()
            let body = CompletionRequest(model: mode == .deep ? settings.deepModel : settings.fastModel,
                                         messages: conversation, max_tokens: task == .bookImport ? 16384 : 8192,
                                         thinking: ["type": mode == .deep ? "enabled" : "disabled"],
                                         reasoning_effort: mode == .deep ? "high" : nil)
            let content = try await completion(body, key: apiKey, deep: mode == .deep)
            do {
                let object = try JSONDecoder().decode(T.self, from: Data(content.utf8))
                try validate(object)
                return object
            } catch {
                if attempt == 1 { throw AppError.ai("AI 连续两次返回了不合格的 JSON 或内容。请重试；本地数据未被修改。") }
                conversation.append(AIMessage(role: "assistant", content: String(content.prefix(24000))))
                conversation.append(AIMessage(role: "user", content: "上一次输出未通过 JSON 结构或内容校验。请严格按原始 schema 重新输出一个完整 JSON 对象，不要代码围栏，不要解释，不要改动原始正确答案。"))
            }
        }
        throw AppError.ai("AI 暂时无法完成请求。")
    }

    private func completion(_ body: CompletionRequest, key: String, deep: Bool) async throws -> String {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else { throw AppError.ai("AI 接口配置无效。") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = deep ? 180 : 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        for attempt in 0...1 {
            do {
                try Task.checkCancellation()
                let (data, response) = try await transport.send(request)
                if [429, 500, 502, 503, 504].contains(response.statusCode) && attempt == 0 {
                    let delay = min(8.0, max(1.0, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)); continue
                }
                switch response.statusCode {
                case 200...299: break
                case 401, 403: throw AppError.ai("DeepSeek API Key 无效或没有访问权限，请在设置中更新。")
                case 402: throw AppError.ai("DeepSeek 账户余额不足，请在 DeepSeek 账户中检查。")
                case 429: throw AppError.ai("DeepSeek 请求过于频繁，稍后再试。")
                case 400, 404: throw AppError.ai("DeepSeek 未接受请求。请检查设置中的模型名称是否仍可用。")
                default: throw AppError.ai("DeepSeek 服务暂时不可用（\(response.statusCode)），本地学习仍可继续。")
                }
                guard data.count <= 8 * 1024 * 1024 else { throw AppError.ai("AI 响应过大，请缩小资料范围。") }
                let decoded: CompletionResponse
                do { decoded = try JSONDecoder().decode(CompletionResponse.self, from: data) }
                catch { throw AppError.ai("AI 服务响应格式异常，请稍后重试。") }
                guard let choice = decoded.choices.first else { throw AppError.ai("AI 没有返回答案。") }
                guard choice.finish_reason == "stop" else { throw AppError.ai("AI 输出未完成或已被截断，请减少内容后重试。") }
                return choice.message.content ?? ""
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                if error.code == .timedOut { throw AppError.ai("AI 请求超时。可以重试，或继续离线学习。") }
                throw AppError.ai("暂时无法连接 DeepSeek，请检查网络。词书、笔记和复习记录仍在本地。")
            }
        }
        throw AppError.ai("AI 请求失败，请稍后重试。")
    }
}
