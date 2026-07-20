import XCTest
@testable import WhisperBox

/// Stubs the JSON-RPC transport: returns queued response bodies (HTTP 200) in order and records
/// each request's decoded JSON body so tests can assert request shaping. XCTest runs serially, so
/// the static state is safe when reset per test.
final class MockURLProtocol: URLProtocol {
    static var responseQueue: [Data] = []
    static var recordedBodies: [[String: Any]] = []

    static func reset() { responseQueue = []; recordedBodies = [] }
    static func enqueueResult(_ result: Any) {
        responseQueue.append(try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "result": result]))
    }
    static func enqueueError(_ message: String) {
        responseQueue.append(try! JSONSerialization.data(withJSONObject:
            ["jsonrpc": "2.0", "id": 1, "error": ["data": ["message": message]]]))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // URLSession delivers the body via httpBodyStream (httpBody is nil here).
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 8192); defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 8192)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.recordedBodies.append(json)
            }
        }
        let body = Self.responseQueue.isEmpty ? Data() : Self.responseQueue.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class OdooServiceTests: XCTestCase {
    private func makeService() -> OdooService {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        var svc = OdooService(config: OdooConfig(baseURL: "https://co.odoo.com/",
                                                 database: "db", login: "me@co", apiKey: "KEY"))
        svc.session = URLSession(configuration: cfg)
        return svc
    }

    override func setUp() { super.setUp(); MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset(); super.tearDown() }

    /// Helper: dig params.args out of a recorded JSON-RPC body.
    private func args(_ body: [String: Any]) -> [Any] {
        ((body["params"] as? [String: Any])?["args"] as? [Any]) ?? []
    }
    private func method(_ body: [String: Any]) -> String {
        (body["params"] as? [String: Any])?["method"] as? String ?? ""
    }

    func testAuthenticateReturnsUidAndSendsCorrectShape() async throws {
        MockURLProtocol.enqueueResult(7)
        let uid = try await makeService().testConnection()
        XCTAssertEqual(uid, 7)

        XCTAssertEqual(MockURLProtocol.recordedBodies.count, 1)
        let body = MockURLProtocol.recordedBodies[0]
        XCTAssertEqual((body["params"] as? [String: Any])?["service"] as? String, "common")
        XCTAssertEqual(method(body), "authenticate")
        XCTAssertEqual(args(body).first as? String, "db")            // database
        XCTAssertEqual(args(body)[1] as? String, "me@co")            // login
        XCTAssertEqual(args(body)[2] as? String, "KEY")              // api key replaces password
    }

    func testAuthFailureThrows() async {
        MockURLProtocol.enqueueResult(false)                          // Odoo returns false on bad creds
        do { _ = try await makeService().testConnection(); XCTFail("should throw") }
        catch { XCTAssertEqual((error as? OdooError)?.errorDescription, OdooError.auth.errorDescription) }
    }

    func testServerErrorMessageSurfaces() async {
        MockURLProtocol.enqueueError("Access Denied")
        do { _ = try await makeService().testConnection(); XCTFail("should throw") }
        catch { XCTAssertTrue("\(error)".contains("Access Denied"), "\(error)") }
    }

    func testPushPrivateArticleFlow() async throws {
        MockURLProtocol.enqueueResult(7)                              // authenticate → uid 7
        MockURLProtocol.enqueueResult([["partner_id": [5, "Me"]]])    // res.users.read → partner 5
        MockURLProtocol.enqueueResult(42)                             // knowledge.article.create → id 42

        let (id, url) = try await makeService().pushPrivateArticle(title: "Notes", bodyHTML: "<p>hi</p>")
        XCTAssertEqual(id, 42)
        XCTAssertTrue(url.contains("id=42"), url)
        XCTAssertTrue(url.contains("model=knowledge.article"), url)

        // Third call = the create; assert it makes a Private article owned by the user.
        XCTAssertEqual(MockURLProtocol.recordedBodies.count, 3)
        let createArgs = args(MockURLProtocol.recordedBodies[2])
        XCTAssertEqual(method(MockURLProtocol.recordedBodies[2]), "execute_kw")
        // execute_kw args: [db, uid, key, model, "create", [vals]]
        XCTAssertEqual(createArgs[3] as? String, "knowledge.article")
        XCTAssertEqual(createArgs[4] as? String, "create")
        let vals = (createArgs[5] as? [Any])?.first as? [String: Any]
        XCTAssertEqual(vals?["internal_permission"] as? String, "none")     // → Private
        XCTAssertEqual(vals?["name"] as? String, "Notes")
        XCTAssertEqual(vals?["body"] as? String, "<p>hi</p>")
        let members = vals?["article_member_ids"] as? [[Any]]
        XCTAssertEqual(members?.first?[2] as? [String: Any] as? [String: AnyHashable],
                       ["partner_id": 5, "permission": "write"])
    }
}
