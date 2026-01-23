import Foundation

/// Parsed result from a base EPUB CFI
public struct ParsedCFI: Equatable {
    /// The spine index (0-based)
    public let spineIndex: Int

    /// Optional idref from the CFI
    public let idref: String?

    public init(spineIndex: Int, idref: String? = nil) {
        self.spineIndex = spineIndex
        self.idref = idref
    }
}

/// Parser for EPUB Canonical Fragment Identifiers (CFI)
/// Supports base CFI format for spine-level addressing
///
/// Base CFI format: `epubcfi(/6/N[idref]!)`
/// - /6 refers to the spine element in the OPF package document
/// - N = (spine_index + 1) * 2 (EPUB uses even numbers for spine items)
/// - [idref] is optional and contains the spine item ID reference
/// - ! marks the end of the package document path
public enum CFIParser {

    /// Parse a base CFI string to extract spine index
    ///
    /// Examples:
    /// - `epubcfi(/6/4[pg-header]!)` -> spineIndex: 1
    /// - `epubcfi(/6/2!)` -> spineIndex: 0
    /// - `epubcfi(/6/8[chapter3]!/4/2)` -> spineIndex: 3 (ignores content path after !)
    ///
    /// - Parameter cfi: The CFI string to parse
    /// - Returns: ParsedCFI if valid, nil otherwise
    public static func parseBaseCFI(_ cfi: String) -> ParsedCFI? {
        // Validate basic structure
        guard cfi.hasPrefix("epubcfi(") && cfi.contains(")") else {
            return nil
        }

        // Extract content between epubcfi( and )
        let startIndex = cfi.index(cfi.startIndex, offsetBy: 8) // "epubcfi(" length
        guard let endIndex = cfi.lastIndex(of: ")") else {
            return nil
        }

        let content = String(cfi[startIndex..<endIndex])

        // Parse the path - looking for /6/N pattern
        // The path should start with /6/ for spine reference
        guard content.hasPrefix("/6/") else {
            return nil
        }

        // Extract the spine step number (the N in /6/N)
        let afterSpine = String(content.dropFirst(3)) // Remove "/6/"

        // Find where the step number ends (at [, !, /, or end)
        var numberString = ""
        var idref: String?
        var i = afterSpine.startIndex

        // Extract the number
        while i < afterSpine.endIndex {
            let char = afterSpine[i]
            if char.isNumber {
                numberString.append(char)
            } else {
                break
            }
            i = afterSpine.index(after: i)
        }

        guard let stepNumber = Int(numberString), stepNumber > 0, stepNumber % 2 == 0 else {
            return nil
        }

        // Check for optional idref in brackets [idref]
        if i < afterSpine.endIndex && afterSpine[i] == "[" {
            let bracketStart = afterSpine.index(after: i)
            if let bracketEnd = afterSpine[bracketStart...].firstIndex(of: "]") {
                idref = String(afterSpine[bracketStart..<bracketEnd])
            }
        }

        // Convert step number to spine index: index = (N / 2) - 1
        let spineIndex = (stepNumber / 2) - 1

        return ParsedCFI(spineIndex: spineIndex, idref: idref)
    }

    /// Generate a base CFI for a given spine index
    ///
    /// - Parameters:
    ///   - spineIndex: The 0-based spine index
    ///   - idref: Optional spine item ID reference
    /// - Returns: A CFI string
    public static func generateBaseCFI(spineIndex: Int, idref: String? = nil) -> String {
        // Convert spine index to step number: N = (index + 1) * 2
        let stepNumber = (spineIndex + 1) * 2

        if let idref = idref {
            return "epubcfi(/6/\(stepNumber)[\(idref)]!)"
        } else {
            return "epubcfi(/6/\(stepNumber)!)"
        }
    }
}
