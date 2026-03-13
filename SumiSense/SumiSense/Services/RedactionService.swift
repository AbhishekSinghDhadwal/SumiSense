import Foundation

protocol RedactionService {
    func redact(text: String, mode: ShareMode) async throws -> RedactionResult

    func warmUp() async throws
}

extension RedactionService {
    func warmUp() async throws {}
}
