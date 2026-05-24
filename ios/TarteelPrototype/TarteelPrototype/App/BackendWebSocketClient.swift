import Foundation

final class BackendWebSocketClient {
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func connect(
        url: URL,
        authorizationToken: String? = nil,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        disconnect()

        var request = URLRequest(url: url)
        if let authorizationToken, !authorizationToken.isEmpty {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()

        do {
            try await waitUntilConnected(task)
        } catch {
            disconnect()
            throw error
        }

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(onEvent: onEvent)
        }
    }

    func send(_ payload: AudioChunkPayload) async throws {
        guard let task else { return }
        let data = try encoder.encode(payload)
        let text = String(decoding: data, as: UTF8.self)
        try await task.send(.string(text))
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receiveLoop(onEvent: @escaping @Sendable (RecitationEvent) -> Void) async {
        guard let task else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if let event = try decodeEvent(from: message) {
                    onEvent(event)
                }
            } catch {
                return
            }
        }
    }

    private func waitUntilConnected(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    private func decodeEvent(from message: URLSessionWebSocketTask.Message) throws -> RecitationEvent? {
        switch message {
        case .data(let data):
            return try decoder.decode(RecitationEvent.self, from: data)
        case .string(let text):
            return try decoder.decode(RecitationEvent.self, from: Data(text.utf8))
        @unknown default:
            return nil
        }
    }
}
