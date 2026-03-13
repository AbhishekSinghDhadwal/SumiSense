import Foundation

final class MelangeTokenizer {
    private var vocab: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]

    var bosId = 0
    var eosId = 2
    var unkId = 3
    var padId = 1

    init() throws {
        try loadVocab()
    }

    private func loadVocab() throws {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "tokenizer", withExtension: "json")
            ?? bundle.url(forResource: "tokenizer", withExtension: "json", subdirectory: "Resources/MelangeAssets")
            ?? bundle.url(forResource: "tokenizer", withExtension: "json", subdirectory: "MelangeAssets")

        guard let url else {
            throw MelangeRuntimeError.resourceMissing("tokenizer.json")
        }

        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MelangeRuntimeError.resourceMissing("tokenizer.json format")
        }

        let vocabCandidate: [String: Any]?
        if let model = json["model"] as? [String: Any] {
            vocabCandidate = model["vocab"] as? [String: Any]
        } else {
            vocabCandidate = json["vocab"] as? [String: Any]
        }

        guard let vocabCandidate else {
            throw MelangeRuntimeError.resourceMissing("tokenizer vocab")
        }

        for (token, idAny) in vocabCandidate {
            if let id = idAny as? Int {
                vocab[token] = id
                idToToken[id] = token
            }
        }

        bosId = vocab["<s>"] ?? bosId
        eosId = vocab["</s>"] ?? eosId
        unkId = vocab["<unk>"] ?? unkId
        padId = vocab["<pad>"] ?? padId
    }

    func encode(_ text: String) -> [Int] {
        var ids = [bosId]
        let prepared = (" " + text).replacingOccurrences(of: " ", with: "\u{0120}")

        let chars = Array(prepared)
        var index = 0

        while index < chars.count {
            var matched = false
            let maxLen = min(20, chars.count - index)

            for length in stride(from: maxLen, through: 1, by: -1) {
                let token = String(chars[index..<index + length])
                if let id = vocab[token] {
                    ids.append(id)
                    index += length
                    matched = true
                    break
                }
            }

            if !matched {
                ids.append(unkId)
                index += 1
            }
        }

        ids.append(eosId)
        return ids
    }

    func decodeToken(_ id: Int) -> String {
        idToToken[id]?.replacingOccurrences(of: "\u{0120}", with: " ") ?? ""
    }

    func rawToken(_ id: Int) -> String? {
        idToToken[id]
    }
}
