import Foundation
import Network

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

/// A small HTTP/1.1 server that only accepts connections from this Mac.
public final class HTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "control-room.server")
    private let handler: @Sendable (HTTPRequest) -> HTTPResponse

    public init(port: Int, handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw RuleError("Bad port \(port).") }
        let params = NWParameters.tcp
        // Bind to 127.0.0.1 itself so nothing on the network can even connect.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)
        self.handler = handler
    }

    /// Starts listening. Calls `ready` once with nil, or with an error if the port is taken.
    public func start(ready: @escaping @Sendable (Error?) -> Void) {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready(nil)
            case .failed(let error): ready(error)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(on: connection, with: self.handler(request))
            } else if isComplete || error != nil || buffer.count > 1_000_000 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    /// Returns a request once the headers and the whole body have arrived.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        return HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]),
                           headers: headers, body: Data(body.prefix(length)))
    }

    private func respond(on connection: NWConnection, with response: HTTPResponse) {
        let reason = [200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found"][response.status] ?? "Error"
        var out = Data("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(response.body)
        connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
    }
}
