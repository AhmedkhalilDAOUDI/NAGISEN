import XCTest
@testable import NAGISEN

final class CoachProviderTests: XCTestCase {
    private let turns = [["role": "user", "content": "hi"]]

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testAnthropicUsesItsOwnHeadersAndTopLevelSystem() throws {
        let request = try CoachProvider.anthropic.request(key: "k", model: "m", customBase: "", system: "sys", messages: turns)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "anthropic-version"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let json = try body(request)
        XCTAssertEqual(json["system"] as? String, "sys")
        XCTAssertEqual((json["messages"] as? [[String: String]])?.count, 1)
    }

    func testOpenAICompatibleProvidersPutTheSystemPromptFirst() throws {
        for provider in [CoachProvider.openAI, .gemini, .deepSeek, .mistral, .openRouter] {
            let request = try provider.request(key: "k", model: "m", customBase: "", system: "sys", messages: turns)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k", provider.name)
            let messages = try XCTUnwrap(body(request)["messages"] as? [[String: String]])
            XCTAssertEqual(messages.first?["role"], "system", provider.name)
            XCTAssertEqual(messages.count, 2, provider.name)
        }
        XCTAssertNotNil(try body(CoachProvider.openAI.request(key: "k", model: "m", customBase: "", system: "", messages: turns))["max_completion_tokens"])
    }

    func testCustomBaseURLGetsTheChatPathAndMustBeHTTPS() throws {
        XCTAssertEqual(CoachProvider.custom.endpoint(customBase: "https://api.groq.com/openai/v1")?.absoluteString,
                       "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(CoachProvider.custom.endpoint(customBase: "https://x.ai/v1/chat/completions")?.absoluteString,
                       "https://x.ai/v1/chat/completions")
        XCTAssertNil(CoachProvider.custom.endpoint(customBase: "http://example.com/v1"))
        XCTAssertThrowsError(try CoachProvider.custom.request(key: "k", model: "m", customBase: "", system: "", messages: turns))
    }

    func testAnswersAreReadFromEitherFormat() {
        let anthropic = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hello"}]}"#
        XCTAssertEqual(CoachProvider.anthropic.answer(from: Data(anthropic.utf8)), "Hello")
        let openAI = #"{"choices":[{"message":{"content":"Hi there"}}]}"#
        XCTAssertEqual(CoachProvider.gemini.answer(from: Data(openAI.utf8)), "Hi there")
        XCTAssertNil(CoachProvider.openAI.answer(from: Data(#"{"choices":[{"message":{"content":"  "}}]}"#.utf8)))
    }

    func testSavedDeepSeekKeysKeepTheirKeychainName() {
        XCTAssertEqual(CoachProvider.deepSeek.keychainAccount, "nagisen.deepseek.api-key")
        XCTAssertNotEqual(CoachProvider.openAI.keychainAccount, CoachProvider.anthropic.keychainAccount)
    }
}
