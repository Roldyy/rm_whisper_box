import Foundation

/// #38 — push meeting notes into Odoo's **Knowledge** app as a *Private* article the
/// connecting user owns. Uses the Odoo External API over **JSON-RPC** (`/jsonrpc`),
/// authenticating with an **API key** (which replaces the password; the login is still
/// required). Knowledge is an Enterprise/Online module and the External API needs a
/// Custom Odoo plan — surfaced as errors if missing.
///
/// Private-article mechanics verified against the Odoo 18 source
/// (`knowledge/models/knowledge_article.py`): a root article with
/// `internal_permission = 'none'` plus the user as a `write` member computes to the
/// `'private'` category. We use plain `create` (RPC-safe, returns the id) rather than
/// the `article_create` method (which returns a recordset that can't cross RPC).
struct OdooConfig {
    let baseURL: String
    let database: String
    let login: String
    let apiKey: String
}

enum OdooError: LocalizedError {
    case notConfigured
    case auth
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Odoo isn't configured — set the URL, database, login, and API key in Settings."
        case .auth:          return "Odoo authentication failed — check the database, login, and API key."
        case .badResponse:   return "Unexpected response from Odoo."
        case .server(let m): return "Odoo error: \(m)"
        }
    }
}

struct OdooService {
    let config: OdooConfig
    /// Injectable for tests (a `URLProtocol` stub); defaults to the shared session.
    var session: URLSession = .shared

    /// Verify credentials; returns the authenticated uid.
    func testConnection() async throws -> Int { try await authenticate() }

    /// Create a Private Knowledge article; returns its id and a link to view it.
    @discardableResult
    func pushPrivateArticle(title: String, bodyHTML: String) async throws -> (id: Int, url: String) {
        let uid = try await authenticate()

        // The connecting user's partner becomes the article's owning member.
        let usersRead = try await executeKw(uid: uid, model: "res.users", method: "read",
                                            args: [[uid], ["partner_id"]])
        guard let rows = usersRead as? [[String: Any]],
              let partnerField = rows.first?["partner_id"] as? [Any],
              let partnerID = partnerField.first as? Int else { throw OdooError.badResponse }

        let vals: [String: Any] = [
            "name": title,
            "body": bodyHTML,
            "internal_permission": "none",   // private: only listed members can access it
            "article_member_ids": [[0, 0, ["partner_id": partnerID, "permission": "write"]]],
        ]
        let created = try await executeKw(uid: uid, model: "knowledge.article", method: "create",
                                          args: [vals])
        let id: Int
        if let i = created as? Int { id = i }
        else if let first = (created as? [Int])?.first { id = first }
        else { throw OdooError.badResponse }

        return (id, "\(trimmedBase())/web#id=\(id)&model=knowledge.article&view_type=form")
    }

    // MARK: - JSON-RPC plumbing

    private func authenticate() async throws -> Int {
        let result = try await call(service: "common", method: "authenticate",
                                    args: [config.database, config.login, config.apiKey, [:]])
        guard let uid = result as? Int, uid > 0 else { throw OdooError.auth }
        return uid
    }

    private func executeKw(uid: Int, model: String, method: String,
                           args: [Any], kwargs: [String: Any] = [:]) async throws -> Any {
        try await call(service: "object", method: "execute_kw",
                       args: [config.database, uid, config.apiKey, model, method, args, kwargs])
    }

    private func call(service: String, method: String, args: [Any]) async throws -> Any {
        guard let url = URL(string: "\(trimmedBase())/jsonrpc") else { throw OdooError.notConfigured }
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "method": "call", "id": 1,
            "params": ["service": service, "method": method, "args": args],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OdooError.server("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OdooError.badResponse
        }
        if let err = dict["error"] as? [String: Any] {
            let msg = (err["data"] as? [String: Any])?["message"] as? String
                ?? err["message"] as? String ?? "unknown error"
            throw OdooError.server(msg)
        }
        return dict["result"] ?? NSNull()
    }

    private func trimmedBase() -> String {
        var s = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // MARK: - Minimal Markdown → HTML for the article body

    /// Odoo `body` is an HTML field; the Claude summary is Markdown. This covers the
    /// common cases (headings, bullets, bold, paragraphs) and escapes the rest.
    static func htmlFromMarkdown(_ md: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        func inline(_ s: String) -> String {
            var out = esc(s)
            while let r = out.range(of: "\\*\\*(.+?)\\*\\*", options: .regularExpression) {
                let inner = out[r].dropFirst(2).dropLast(2)
                out.replaceSubrange(r, with: "<b>\(inner)</b>")
            }
            return out
        }
        var html = ""
        var inList = false, inQuote = false
        func closeList() { if inList { html += "</ul>"; inList = false } }
        func closeQuote() { if inQuote { html += "</blockquote>"; inQuote = false } }
        func closeBlocks() { closeList(); closeQuote() }
        func isRule(_ s: String) -> Bool {
            s.count >= 3 && (Set(s) == ["-"] || Set(s) == ["*"] || Set(s) == ["_"])
        }

        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { closeBlocks(); continue }
            if isRule(line) { closeBlocks(); html += "<hr>"; continue }
            if line.hasPrefix("### ") { closeBlocks(); html += "<h3>\(inline(String(line.dropFirst(4))))</h3>"; continue }
            if line.hasPrefix("## ")  { closeBlocks(); html += "<h2>\(inline(String(line.dropFirst(3))))</h2>"; continue }
            if line.hasPrefix("# ")   { closeBlocks(); html += "<h2>\(inline(String(line.dropFirst(2))))</h2>"; continue }
            if line.hasPrefix(">") {
                closeList()
                if !inQuote { html += "<blockquote>"; inQuote = true }
                var content = String(line.dropFirst())
                if content.hasPrefix(" ") { content.removeFirst() }
                html += "\(inline(content))<br>"
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                closeQuote()
                if !inList { html += "<ul>"; inList = true }
                html += "<li>\(inline(String(line.dropFirst(2))))</li>"
                continue
            }
            closeBlocks()
            html += "<p>\(inline(line))</p>"
        }
        closeBlocks()
        return html.isEmpty ? "<p></p>" : html
    }
}
