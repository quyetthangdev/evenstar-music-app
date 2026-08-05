import Foundation

/// Answers every request from a queue the test sets up, so no test in this
/// suite touches the network.
final class StubURLProtocol: URLProtocol {
    struct Response {
        let status: Int
        let body: Data
    }

    nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    static func reset() {
        responses = []
        requestedURLs = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requestedURLs.append(url) }
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let next = Self.responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
