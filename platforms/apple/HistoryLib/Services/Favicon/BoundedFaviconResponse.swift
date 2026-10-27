import Foundation

/// A per-task receiver: reject before appending bytes, including decoded bodies
/// with absent or misleading Content-Length. No complete-body URLSession API.
nonisolated final class BoundedFaviconResponse: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private let lock = NSLock()
    private var body = Data()
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Data?, Never>?
    private var finished = false

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    static func data(for request: URLRequest, session: URLSession, maximumBytes: Int) async -> Data? {
        let receiver = BoundedFaviconResponse(maximumBytes: maximumBytes)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { receiver.start(request, session: session, continuation: $0) }
        } onCancel: {
            receiver.finish(success: false, cancel: true)
        }
    }

    private func start(_ request: URLRequest, session: URLSession, continuation: CheckedContinuation<Data?, Never>) {
        let task = session.dataTask(with: request)
        task.delegate = self
        lock.lock()
        guard !finished else {
            lock.unlock()
            task.cancel()
            continuation.resume(returning: nil)
            return
        }
        self.task = task
        self.continuation = continuation
        lock.unlock()
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              (200..<400).contains(response.statusCode),
              response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel)
            finish(success: false, cancel: true)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= maximumBytes - body.count else {
            lock.unlock()
            finish(success: false, cancel: true)
            return
        }
        body.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(success: error == nil, cancel: false)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(success: false, cancel: true)
    }

    private func finish(success: Bool, cancel: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let result = success && !body.isEmpty ? body : nil
        let continuation = continuation
        let task = task
        self.continuation = nil
        self.task = nil
        body = Data()
        lock.unlock()
        if cancel { task?.cancel() }
        continuation?.resume(returning: result)
    }
}
