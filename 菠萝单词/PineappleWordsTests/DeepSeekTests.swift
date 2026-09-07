import XCTest
import PineappleCore
@testable import PineappleWords

private actor StubTransport: AIHTTPTransport {
    enum Reply: Sendable { case content(String), status(Int), network(URLError.Code), waiting }
    private var replies: [Reply]
    private var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func captured() -> [URLRequest] { requests }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw AppError.ai("测试响应队列为空") }
        let reply = replies.removeFirst()
        let code: Int, data: Data
        switch reply {
        case .content(let text):
            code = 200
            data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text], "finish_reason": "stop"]]])
        case .status(let value): code = value; data = Data()
        case .network(let code): throw URLError(code)
        case .waiting: try await Task.sleep(nanoseconds: 10_000_000_000); throw CancellationError()
        }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [:]) else {
            throw AppError.ai("测试 URL 无效")
        }
        return (data, response)
    }
}

final class DeepSeekTests: XCTestCase {
    private func request(_ transport: StubTransport, settings: UserSettings = UserSettings(), task: AITask = .chat) async throws -> AIAnswer {
        try await DeepSeekService(transport: transport).structured(AIAnswer.self, task: task, question: "apple 是什么意思", messages: [AIMessage(role: "user", content: "json")], settings: settings, apiKey: "unit-test-key") {
            guard !$0.answer.isEmpty else { throw AppError.invalidData("空答案") }
        }
    }
    func testMalformedJSONRetriesExactlyOnce() async throws {
        let transport = StubTransport([.content("not JSON"), .content("{\"answer\":\"苹果\"}")])
        let result = try await request(transport)
        XCTAssertEqual(result.answer, "苹果")
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 2)
        let body = try XCTUnwrap(requests[1].httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((object["messages"] as? [[String: String]])?.count, 3)
    }
    func testTwoInvalidResponsesReturnChineseError() async {
        let transport = StubTransport([.content("bad"), .content("bad")])
        do { _ = try await request(transport); XCTFail("应拒绝非法 JSON") }
        catch { XCTAssertTrue(error.localizedDescription.contains("连续两次")) }
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 2)
    }
    func testEmptyContentIsRetried() async throws {
        let transport = StubTransport([.content(""), .content("{\"answer\":\"完成\"}")])
        let answer = try await request(transport); XCTAssertEqual(answer.answer, "完成")
    }
    func testInvalidKeyDoesNotRetry() async {
        let transport = StubTransport([.status(401)])
        do { _ = try await request(transport); XCTFail("应拒绝错误 Key") }
        catch { XCTAssertTrue(error.localizedDescription.contains("API Key")) }
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
    }
    func testTimeoutAndOfflineHaveReadableErrors() async {
        for code in [URLError.Code.timedOut, .notConnectedToInternet] {
            do { _ = try await request(StubTransport([.network(code)])); XCTFail("应返回连接错误") }
            catch { XCTAssertTrue(error.localizedDescription.contains(code == .timedOut ? "超时" : "网络")) }
        }
    }
    func testForcedDeepUsesCurrentConfiguredModelAndThinking() async throws {
        var settings = UserSettings(); settings.aiMode = .fast; settings.deepModel = "configured-deep-model"
        let transport = StubTransport([.content("{\"answer\":\"完成\"}")])
        _ = try await request(transport, settings: settings, task: .bookImport)
        let requests = await transport.captured()
        let body = try XCTUnwrap(requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "configured-deep-model")
        XCTAssertEqual((object["thinking"] as? [String: String])?["type"], "enabled")
        XCTAssertEqual((object["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertNil(object["temperature"])
    }
    func testFastModeExplicitlyDisablesDefaultThinking() async throws {
        let transport = StubTransport([.content("{\"answer\":\"苹果\"}")]); _ = try await request(transport)
        let requests = await transport.captured(), body = try XCTUnwrap(requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((object["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(object["reasoning_effort"])
    }
    func testCancellationPropagates() async throws {
        let transport = StubTransport([.waiting])
        let operation = Task { try await request(transport) }
        try await Task.sleep(nanoseconds: 100_000_000)
        operation.cancel()
        do { _ = try await operation.value; XCTFail("应被取消") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
