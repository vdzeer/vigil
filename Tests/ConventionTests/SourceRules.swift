import Foundation
import Testing

/// Rules of the project, checked against the source text itself.
@Suite struct SourceRules {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static func lines(under folder: String, keepComments: Bool) -> [(file: String, number: Int, text: String)] {
        let base = root.appendingPathComponent(folder)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var found: [(String, Int, String)] = []
        for case let url as URL in walker where ["swift", "sh"].contains(url.pathExtension) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                // Comments are prose for developers, not code: `//` in Swift, `#` in shell scripts.
                let marker = url.pathExtension == "sh" ? "#" : "//"
                let code = keepComments ? line : line.range(of: marker).map { String(line[..<$0.lowerBound]) } ?? line
                found.append((url.lastPathComponent, index + 1, code))
            }
        }
        return found
    }

    static func offences(
        _ pattern: String, in folders: [String], only file: String? = nil, keepComments: Bool = false
    ) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return folders.flatMap { lines(under: $0, keepComments: keepComments) }.compactMap { line in
            if let file, line.file != file { return nil }
            let range = NSRange(line.text.startIndex..., in: line.text)
            return regex.firstMatch(in: line.text, range: range) == nil ? nil : "\(line.file):\(line.number)"
        }
    }

    @Test func theAppIsInEnglishOnly() {
        #expect(
            Self.offences(#"\p{Cyrillic}"#, in: ["Sources", "Resources", "scripts", "Tests"], keepComments: true) == [])
    }

    @Test func wordsLiveInTheStringsFile() {
        // A string literal with a capitalised word and a space is UI copy; it belongs in Strings.swift.
        let copy = Self.offences(#""[A-Z][a-z]+ [a-z][^"]*""#, in: ["Sources"])
            .filter { !$0.hasPrefix("Strings.swift") && !$0.hasPrefix("main.swift") }
        #expect(copy == [])
    }

    @Test func copyHasNoExclamationMarksOrStraightApostrophes() {
        #expect(Self.offences(#""[^"]*![^"=]*""#, in: ["Sources"], only: "Strings.swift") == [])
        #expect(Self.offences(#"[A-Za-z]'[a-z]"#, in: ["Sources"], only: "Strings.swift") == [])
    }

    @Test func thePasswordDialogNamesVigil() {
        // Through osascript the dialog would name osascript instead of Vigil.
        #expect(Self.offences(#"/usr/bin/osascript"#, in: ["Sources"]) == [])
    }

    @Test func commandsAreCalledByTheirFullPath() {
        // `run` takes an executable path, never a name looked up in PATH.
        #expect(Self.offences(#"run\("[a-z]"#, in: ["Sources"]) == [])
    }
}
