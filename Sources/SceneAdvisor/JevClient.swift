import Foundation

/// TypeSafe AI の Jev（`POST /v1/systemone`）に、画像 1 枚と質問を送る。
///
/// Jev は、質問ごとに型のある答え（はい/いいえの確からしさ、選択肢ごとの確からしさ、枠）を返すモデル。画像と枠の質問は
/// 試作向けの機能（TypeSafe が本番には勧めていない）で、形や制限が変わりうる。
/// 画像は、辺が 280〜1568 画素、画素数が 78,400〜2,458,624 に収まっていること（外れると、縮めずに断られる）。
public struct JevClient: Sendable {
    public var apiKey: String
    public var endpoint: URL
    public var model: String
    public var session: URLSession

    public init(
        apiKey: String,
        endpoint: URL = URL(string: "https://api.typesafe.ai/v1/systemone")!,
        model: String = "jev-1.14.0",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    /// 質問 1 つ。
    public enum Question: Sendable, Equatable {
        /// はい/いいえ。答えは、はいの確からしさ（0〜1）。
        case yesNo(String)
        /// 選択肢から 1 つ。`options` は、選択肢の名前から説明へ。答えは、選択肢ごとの確からしさ。
        case choice(String, options: [String: String])
    }

    /// 答え 1 つ。
    public enum Answer: Sendable, Equatable {
        case yesNo(Double)
        case choice(String, probabilities: [String: Double])
    }

    public enum Failure: Error, Equatable {
        case http(status: Int, body: String)
        case malformed(String)
    }

    /// `jpeg`（画像）を `photo` という名前で見せて、`questions` を聞く。質問の文の中では、画像を `` `photo` `` と呼ぶ。
    public func ask(jpeg: Data, questions: [String: Question]) async throws -> [String: Answer] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
        request.httpBody = try Self.body(model: model, jpeg: jpeg, questions: questions)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.http(status: status, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        return try Self.answers(from: data)
    }

    /// 画像を指す名前。質問の文の中の言葉と取り違えないよう、ふつうは出てこない文字列にする。
    static let imageReference = "c7e2a9f4-frame"

    static func body(model: String, jpeg: Data, questions: [String: Question]) throws -> Data {
        var encoded = [String: Any]()
        for (name, question) in questions {
            switch question {
            case let .yesNo(instructions):
                encoded[name] = ["type": "noul", "instructions": instructions]
            case let .choice(instructions, options):
                encoded[name] = ["type": "choice", "instructions": instructions, "criteria": options]
            }
        }
        let body: [String: Any] = [
            "model": model,
            "state": ["photo": imageReference],
            "assets": [imageReference: ["type": "image", "format": "jpg", "data_base64": jpeg.base64EncodedString()]],
            "questions": encoded
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func answers(from data: Data) throws -> [String: Answer] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: [String: Any]] else {
            throw Failure.malformed("answers が無い")
        }
        var result = [String: Answer]()
        for (name, answer) in answers {
            switch answer["type"] as? String {
            case "noul":
                guard let value = answer["noul"] as? Double else { throw Failure.malformed("\(name) の noul が無い") }
                result[name] = .yesNo(value)
            case "choice":
                guard let choice = answer["choice"] as? String, let probabilities = answer["probabilities"] as? [String: Double] else {
                    throw Failure.malformed("\(name) の choice が無い")
                }
                result[name] = .choice(choice, probabilities: probabilities)
            default:
                continue
            }
        }
        return result
    }
}
