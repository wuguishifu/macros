/// A macro register, `a` through `z`.
public struct Register: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let letter: Character

    /// Accepts a single lowercase or uppercase ASCII letter; uppercase is normalized to lowercase.
    public init?(_ character: Character) {
        guard let ascii = character.lowercased().first?.asciiValue, (97...122).contains(ascii) else { return nil }
        letter = Character(UnicodeScalar(ascii))
    }

    public init?(_ string: String) {
        guard string.count == 1, let character = string.first else { return nil }
        self.init(character)
    }

    public static let all: [Register] = (UInt8(97)...UInt8(122)).compactMap { Register(Character(UnicodeScalar($0))) }

    public var description: String { String(letter) }

    public static func < (lhs: Register, rhs: Register) -> Bool { lhs.letter < rhs.letter }
}

extension Register: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let register = Register(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid register \(string)")
        }
        self = register
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
