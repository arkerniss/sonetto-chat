import Foundation

/// WebDAV 备份配置。密码不存这里(走 Keychain),与供应商 API Key 的做法一致。
struct WebDAVConfig: Codable, Equatable {
    var urlString = ""
    var username = ""
    var path = "sonetto_backups"
    var includeConversations = true
    var includeAttachments = true
}

struct WebDAVBackupItem: Identifiable, Equatable {
    let href: String
    let displayName: String
    let size: Int64
    let lastModified: Date?

    var id: String { href }
}

enum WebDAVError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "WebDAV 地址无效,请检查服务器地址和路径"
        case .unauthorized:
            return "认证失败,请检查用户名和密码"
        case let .serverError(code):
            return "服务器返回错误(HTTP \(code))"
        case .parseFailed:
            return "无法解析服务器返回的文件列表"
        }
    }
}

/// 仿 rikkahub 的 WebDavClient:不引第三方库,直接用 URLSession 发
/// PROPFIND / MKCOL / PUT / GET / DELETE,Basic 认证。
struct WebDAVClient {
    private let serverURL: URL
    private let directoryURL: URL
    private let authorization: String
    private let session: URLSession

    init(config: WebDAVConfig, password: String) throws {
        let trimmed = config.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            throw WebDAVError.invalidURL
        }

        serverURL = url
        var directory = url
        for segment in config.path.split(separator: "/") {
            directory.appendPathComponent(String(segment), isDirectory: true)
        }
        directoryURL = directory

        let credentials = Data("\(config.username):\(password)".utf8).base64EncodedString()
        authorization = "Basic \(credentials)"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    /// 测试连接:对服务器根做 depth 0 的 PROPFIND(rikkahub 同款做法)
    func testConnection() async throws {
        var request = makeRequest(url: serverURL, method: "PROPFIND")
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.httpBody = Self.propfindBody
        _ = try await perform(request, allowed: [200, 207, 301])
    }

    /// 备份目录不存在则创建。405 表示已存在,视为成功。
    func ensureDirectory() async throws {
        let request = makeRequest(url: directoryURL, method: "MKCOL")
        _ = try await perform(request, allowed: [200, 201, 405, 301])
    }

    func upload(_ data: Data, filename: String) async throws {
        var request = makeRequest(url: fileURL(filename), method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try await perform(request, allowed: [200, 201, 204])
    }

    /// 列出备份目录下 backup_*.json 文件,按时间倒序
    func list() async throws -> [WebDAVBackupItem] {
        var request = makeRequest(url: directoryURL, method: "PROPFIND")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.httpBody = Self.propfindBody
        let data = try await perform(request, allowed: [200, 207])

        let parser = WebDAVListParser()
        guard let items = parser.parse(data) else {
            throw WebDAVError.parseFailed
        }

        return items
            .filter { $0.displayName.hasPrefix("backup_") && $0.displayName.hasSuffix(".json") }
            .sorted { $0.displayName > $1.displayName }
    }

    func download(filename: String) async throws -> Data {
        let request = makeRequest(url: fileURL(filename), method: "GET")
        return try await perform(request, allowed: [200])
    }

    func delete(filename: String) async throws {
        let request = makeRequest(url: fileURL(filename), method: "DELETE")
        _ = try await perform(request, allowed: [200, 204])
    }

    // MARK: - 内部

    private static let propfindBody = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:displayname/>
        <d:getcontentlength/>
        <d:getlastmodified/>
        <d:resourcetype/>
      </d:prop>
    </d:propfind>
    """.utf8)

    private func fileURL(_ filename: String) -> URL {
        directoryURL.appendingPathComponent(filename)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest, allowed: Set<Int>) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.serverError(0)
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard allowed.contains(http.statusCode) else {
            throw WebDAVError.serverError(http.statusCode)
        }
        return data
    }
}

/// 解析 PROPFIND 的 207 multistatus XML
private final class WebDAVListParser: NSObject, XMLParserDelegate {
    private var items: [WebDAVBackupItem] = []
    private var currentHref = ""
    private var currentName = ""
    private var currentSize: Int64 = 0
    private var currentModified: Date?
    private var isCollection = false
    private var currentText = ""

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    func parse(_ data: Data) -> [WebDAVBackupItem]? {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        guard parser.parse() else {
            return nil
        }
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentText = ""
        if elementName == "response" {
            currentHref = ""
            currentName = ""
            currentSize = 0
            currentModified = nil
            isCollection = false
        } else if elementName == "collection" {
            isCollection = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href":
            currentHref = text
        case "displayname":
            currentName = text
        case "getcontentlength":
            currentSize = Int64(text) ?? 0
        case "getlastmodified":
            currentModified = Self.httpDateFormatter.date(from: text)
        case "response":
            // displayname 可能为空,从 href 兜底取文件名
            let name = currentName.isEmpty
                ? (currentHref.removingPercentEncoding ?? currentHref)
                    .split(separator: "/").last.map(String.init) ?? ""
                : currentName
            if !isCollection, !name.isEmpty {
                items.append(WebDAVBackupItem(
                    href: currentHref,
                    displayName: name,
                    size: currentSize,
                    lastModified: currentModified
                ))
            }
        default:
            break
        }
    }
}
