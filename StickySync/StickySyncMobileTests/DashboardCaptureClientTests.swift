// DashboardCaptureClientTests.swift
//
// 0.12.17: pin the request-shape contract with the dashboard's
// /api/capture endpoint (see docs/dashboardcapture.md). We can't
// hit the endpoint from CI/tests, so we intercept the request via
// URLProtocol and assert:
//   - correct URL + token query param
//   - correct HTTP method + Content-Type
//   - correct JSON body shape

import XCTest
@testable import StickySyncMobile

final class DashboardCaptureClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.captured = nil
        StubURLProtocol.responseBody = Data("""
            {"captured":1,"did":"captured 1 item","items":[]}
            """.utf8)
        StubURLProtocol.status = 200
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    func testRequestShape() async throws {
        let config = DashboardConfig(
            endpoint: URL(string: "https://example.test/api/capture"),
            token: "secret-token-xyz",
            afterSend: .keep)

        _ = try await DashboardCaptureClient.send("hello world", config: config)

        let req = try XCTUnwrap(StubURLProtocol.captured)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let url = try XCTUnwrap(req.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://example.test/api/capture?"))
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.queryItems?.first(where: { $0.name == "token" })?.value,
                       "secret-token-xyz")

        // Body streamed via bodyStream when URLProtocol intercepts;
        // fall back to httpBodyStream if httpBody is nil.
        let body = req.httpBody ?? StubURLProtocol.capturedBody
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: String]
        XCTAssertEqual(json?["text"], "hello world")
    }

    func testNotConfiguredThrows() async {
        let config = DashboardConfig(endpoint: nil, token: "", afterSend: .keep)
        do {
            _ = try await DashboardCaptureClient.send("x", config: config)
            XCTFail("Expected notConfigured error")
        } catch DashboardCaptureError.notConfigured {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testHttpErrorMapsToHttpStatus() async {
        StubURLProtocol.status = 401
        StubURLProtocol.responseBody = Data("""
            {"error":"bad or missing token"}
            """.utf8)
        let config = DashboardConfig(
            endpoint: URL(string: "https://example.test/api/capture"),
            token: "wrong",
            afterSend: .keep)
        do {
            _ = try await DashboardCaptureClient.send("x", config: config)
            XCTFail("Expected httpStatus error")
        } catch DashboardCaptureError.httpStatus(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}

private final class StubURLProtocol: URLProtocol {
    static var captured: URLRequest?
    static var capturedBody: Data?
    static var responseBody: Data = Data()
    static var status: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured = request
        // URLProtocol strips httpBody, moves it to httpBodyStream;
        // read it back so tests can assert on the payload.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 4096)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            Self.capturedBody = data
        }
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
